require 'watir-webdriver'
require 'optparse'
require 'optparse/date'
require 'pry'
require 'ostruct'
require 'csv'
require 'pp'

STDOUT.sync = true

o = OpenStruct.new
o.username = nil
o.password = nil
o.from = nil
o.to = nil
o.start = nil
o.end = nil
opt_parser = OptionParser.new do |opts|
  opts.banner = "Usage: tbscrape.rb [options]"
  opts.on("-u", "--user USER", "Topbonus username") do |u|
    o.username = u
  end
  # whatever
  opts.on("-p", "--password PASS", "Topbonus password") do |p|
    o.password = p
  end

  opts.on("-f", "--from SEARCH", "From airport, airberlin search. First will be selected") do |f|
    o.from = f
  end
  # whatever
  opts.on("-t", "--to SEARCH", "To airport, airberlin search. First will be selected") do |t|
    o.to = t
  end

  opts.on("-s", "--start DATE", Date, "Search start date, format YYYY-MM-DD") do |s|
    o.start = s
  end
  opts.on("-e", "--end DATE", Date, "Search end date, format YYYY-MM-DD") do |e|
    o.end = e
  end
end.parse!(ARGV)

mandatory = [:username, :password, :from, :to, :start, :end]
missing = mandatory.select{ |param| o[param].nil? }
unless missing.empty?
  STDERR.puts "Missing options: #{missing.join(', ')}"
  STDERR.puts opt_parser
  exit 1
end

# Firefox less effort
@b = Watir::Browser.new :firefox
trap("SIGINT") { @b.close;exit }

def say(msg)
  STDERR.puts "--> #{msg}"
end

def fatal(msg)
  say msg
  binding.pry if ENV['DEBUG']
  @b.close
  exit 1
end

SEARCH_PAGE = "http://www.airberlin.com/site/abflugplan.php?LANG=eng&woher=miles&ab_source=en_site_tb_partner_index_php_cid3_AA_redeem&ab_medium=website&ab_campaign=tb-praemienflug&ab_content=button_top"

# Log in
say "Attempting to log in"
@b.goto("https://www.airberlin.com")
@b.link(:text =>"Log-in").when_present.click
frm = @b.form(name: "yabLoginForm")
frm.text_fields.find {|f| f.name =~ /^login/}.set o.username
frm.text_fields.find {|f| f.name =~ /^pass/}.set o.password
@b.button(:text =>"Log-in").click

# Check log in state
if !@b.button(:text =>"Log-out").exists?
  fatal "No logout button found, check creds"
end

say "Logged in. Starting flight search"
# Get the flight search page loaded.
# TODO - this will be the date loop point

say "Loading search page"
@b.goto(SEARCH_PAGE)

srch_date = o.start

say "Starting searches"

# Print a header
r = CSV::Row.new([],[],true)
r << "date"
r << "ov_time"
r << "ov_stops"
r << "ov_duration"
r << "ov_miles"
r << "ov_money"
r << "ov_rem_seats"
# Assume max of 4 changeovers
(1..4).each do |didx|
  r << "depart_#{didx}"
  r << "arrive_#{didx}"
  r << "flight_#{didx}"
  r << "carrier_#{didx}"
end
STDOUT.puts r

# Make sure no more loading
Watir::Wait.until { !@b.div(class: "loadingbanner").exists? }
# And wait a little more for unknown thing loading
sleep 3

frm = @b.form(id: "flightSearchForm")

# Departure
frm.text_field(id: "departure").set(o.from)
dept_div = @b.div(class: "routing").divs(xpath: './*').first
dept_div.div(class: "fullsuggest-open").wait_until_present
if dept_div.div(class: "suggestcontainer").divs.size < 1
  fatal("No suggestions for departure")
end
dept_div.div(class: "suggestcontainer").divs.first.click

# Destination
frm.text_field(id: "destination").set(o.to)
dest_div = @b.div(class: "routing").divs(xpath: './*').last
dest_div.div(class: "fullsuggest-open").wait_until_present
if dest_div.div(class: "suggestcontainer").divs.size < 1
  fatal("No suggestions for departure")
end
dest_div.div(class: "suggestcontainer").divs.first.click

retries = 0
while srch_date < o.end
  say "Starting search from #{o.from} to #{o.to} on #{srch_date}"

  retries = 0
  begin
    # One way
    @b.checkbox(id: "oneway").set

    # Date. format as yyyy-mm-dd
    @b.text_field(id: "outbounddate").click
    date_div = @b.div(id: "outbound-date")
    date_div.wait_until_present
    date_div.select(:class, 'ui-datepicker-new-year').select_value(srch_date.year)
    date_div.select(:class, 'ui-datepicker-new-month').select(srch_date.strftime("%B"))
    date_div.table(:class, 'ui-datepicker').link(text: srch_date.day.to_s).click

    # GOGO
    @b.button(:text =>"Search for flights").click

    # Wait for loading banner to come and go
    Watir::Wait.until { @b.div(class: "loadingbanner").exists? }
    Watir::Wait.until { !@b.div(class: "loadingbanner").exists? }

    # Kinda hacky, but whatevs. Alt, I think the real target is div#block #blockUI (or #blockOverlay?)
    Watir::Wait.until do
      @b.div(id: "flighttables").exists? ||
        (@b.div(id: "vacancy_dateoverview").exists? && @b.div(id: "vacancy_dateoverview").elements.count > 0) ||
        (@b.div(id: "vacancy_error").exists? && @b.div(id: "vacancy_error").elements.count > 0)
    end

    # Only written if we have flights
    if @b.div(id: "flighttables").exists?
      @b.trs(class: "flightrow").each_with_index do |tr,idx|
        r = CSV::Row.new([],[])
        tr.td(class: "flightdetailstoggle").click

        Watir::Wait.until { @b.div(class: "icon loading").exists? }
        Watir::Wait.until { !@b.div(class: "icon loading").exists? }

        # Get the overview of the flight
        r << ["date", srch_date]
        r << ["ov_time", tr.tds[1].text]
        r << ["ov_stops", tr.tds[2].text]
        r << ["ov_duration", tr.tds[3].text]
        r << ["ov_miles", tr.tds[4].text]
        r << ["ov_money", @b.div(id: "vacancy_priceoverview").table(class: "total").trs[1].tds[0].text]
        r << ["ov_rem_seats", @b.div(class: "remainingseats").text.split("\n").last]
        # Get the legs
        @b.trs(class: "flightdetails")[idx].tbody.trs.each_with_index do |dtr,didx|
          r << ["depart_#{didx}", dtr.tds[1].text]
          r << ["arrive_#{didx}", dtr.tds[2].text]
          r << ["flight_#{didx}", dtr.tds[3].text]
          r << ["carrier_#{didx}", dtr.tds[4].text]
        end
        puts r
      end
      # No flights, but others nearby. Maybe can optimize skipping dates with this in the future?
    elsif @b.div(id: "vacancy_dateoverview").exists? && @b.div(id: "vacancy_dateoverview").elements.count > 0
      say "No flights found from #{o.from} to #{o.to} on #{srch_date}, but flights in the vincinity"
      # This is nothing found, with nothing in the timeframe
      # TODO - confirm that this is the same for "invalid route" as "nothing near date"?
    elsif @b.div(id: "vacancy_error").exists? && @b.div(id: "vacancy_error").elements.count > 0
      say "No flights found from #{o.from} to #{o.to} on #{srch_date}"
    else
      # Shouldn't hit this anymore because of the wait above
      fatal "Unknown error page loaded"
    end

    # Pop the search box open if it isn't already
    @b.link(id: "changeSearch").click unless @b.div(class: "routing").visible?
  rescue Exception => e
    if retries > 5
      fatal "Too many retries on the same page"
    end
    say "Error occured: #{e}. Re-loading search page and trying again"
    @b.goto(SEARCH_PAGE)
    retries += 1
    next
  end

  # Move on to the next day, reset retries
  srch_date += 1
  retries = 0
end

say "Search complete"
@b.close
