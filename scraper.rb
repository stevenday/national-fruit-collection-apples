require 'scraperwiki'
require 'mechanize'

BASE_URL = "http://www.nationalfruitcollection.org.uk"
INDEX_URL = "#{BASE_URL}/a-z.php"


agent = Mechanize.new

apple_urls = []

# Currently 2000ish apples, so this will last a while
p "Getting apple urls from index"
0.step(100000, 100) do |i|
  p "Checking page #{i}"
  page = agent.post(INDEX_URL, {startresult: i, fruit: "apple"})
  links = page.links_with(class: 'infolink')
  # Site returns an empty page when there's no more apples
  page_urls = links.map(&:href)
  if page_urls.empty?
    p "No more apples"
    break
  else
    p "Saving #{page_urls.count} to master list"
    apple_urls.concat page_urls
    # Don't hammer the site
    sleep(1)
  end
end

p "Found #{apple_urls.count} apples in total"

apple_urls.each do |url|
  begin
    p "Checking #{url}"
    full_url = "#{BASE_URL}/#{url}"
    # For testing without loading all the other stuff first
    # full_url = "http://www.nationalfruitcollection.org.uk/full2.php?varid=6991&&acc=2000104&&fruit=apple"
    page = agent.get(full_url)

    main_content = page.search("#main-copy")

    name_h1 = main_content.search("h1")
    name = name_h1.text

    latin_name_h2 = main_content.search("h2")
    if latin_name_h2
      latin_name = latin_name_h2.text
    else
      latin_name = nil
    end

    main_category_p = name_h1.xpath("following-sibling::p/b")
    if main_category_p
      main_category = main_category_p.text
    else
      main_category = nil
    end

    if latin_name_h2
      description_p = latin_name_h2.xpath("following-sibling::p")
      if description_p
        description = description_p.text
      else
        description = nil
      end
    else
      description = main_category
      main_category = nil
    end

    # Get all the <dl> data elements there are
    data = {}
    # Stupid &nbsp; break our text parsing
    nbsp = Nokogiri::HTML("&nbsp;").text
    main_content.search("dl.data").search("dt").each do |term|
      term_field_name = term.text.downcase.gsub(/[:\(\)›]/, "").strip.gsub(nbsp, "").gsub(/\s+/, "_")
      # TODO: store references for fields separately
      if term_field_name == "references"
        next
      end
      term_text = term.next_element.text.gsub(/\s+[12]$/, "").strip.gsub(nbsp, " ")
      data[term_field_name] = term_text
    end

    data.merge!({
      "url" => full_url,
      "name" => name,
      "latin_name" => latin_name,
      "main_category" => main_category
    })

    p data

    # Write out to the sqlite database using scraperwiki library
    ScraperWiki.save_sqlite(["url"], data)
  rescue Exception => e
    # Don't let one thing ruin all the others
    p e.message
  end
end

