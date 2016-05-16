# Airberlin/Topbonus award scraper

Jank script to search for reward available on topbonus

## Usage

	Usage: bundle exec ruby tbscrape.rb [options]
    -u, --user USER                  Topbonus username
    -p, --password PASS              Topbonus password
    -f, --from SEARCH[,SEARCH]       From airport, airberlin search. First will be selected. Can be comma delimited list
    -t, --to SEARCH[,SEARCH]         To airport, airberlin search. First will be selected. Can be comma delimited list
    -s, --start DATE                 Search start date, format YYYY-MM-DD
    -e, --end DATE                   Search end date, format YYYY-MM-DD
