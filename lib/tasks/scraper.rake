require 'csv'

namespace :scraper do
  desc "Scrape pepperjamnetwork.com for program info and scan for bidding policy"
  task pepperjam: :environment do
    time_start = Time.now
    start_point = 0

    # Initiate a ICONV object to convert/uniform encodings to utf-8
    encoding_converter = Iconv.new('UTF-8', 'LATIN1')

    # Initiate a Mechanize object, request for pepperjam site and log in with credentials.
    agent = Mechanize.new
    target_host = 'http://www.pepperjamnetwork.com'
    agent.get(target_host) do |page|
      login_form = page.form_with(name: 'login') do |form|
        form.email = ENV['PEPPERJAM_UN']
        form.passwd = ENV['PEPPERJAM_PW']
      end
      login_form.submit
    end

    # Once logged in, fetch & parse through csv file to extract all available program ids
    csv_raw_data = agent.get("#{target_host}/affiliate/program/manage?&csv=1")
    csv_into_array = CSV.parse(csv_raw_data.body)
    csv_into_array.shift # drop the headings
    prgm_ids_array = csv_into_array.map! { |x| x[0] }
    puts "UPDATE: Total of #{prgm_ids_array.count} programs available"

    # Iterate thru program ids, retrieve detail information and save them into database
    scraping_count = 0

    prgm_ids_array.count.times do |i|
      prgm_url = "#{target_host}/affiliate/program/popup?programId=#{prgm_ids_array[i]}"
      prgm_page = agent.get(prgm_url)
      desc_page = agent.get("#{target_host}/affiliate/program/description?programId=#{prgm_ids_array[i]}")

      # Shortcuts
      header = prgm_page.search('.program-header')
      tabcontents = prgm_page.search('.tab-content')

      # Variables used to calculate other properties
      company_name = header.css('.program-name').text.gsub(/^\s+|\s+$/, "")
      description = desc_page.search('.pd_desc').text.gsub(/^\s+|\s+$/, "")
      restricted_keywords = check_capture_keywords(encoding_converter, tabcontents[4], "Restricted Keywords:")

      Program.create(
        prgm_count:           i + 1,
        prgm_id:              prgm_ids_array[i],
        prgm_url:             prgm_url,
        company_name:         company_name,
        logo_url:             check_capture_logo_url(header),
        site_address:         header.css('.websiteurl').text(),
        categories:           header.css('.base-info div')[1].children[2].text.gsub(/^\s+|\s+$/, ""),
        mobile_tracking:      header.css('.base-info div')[2].children[2].text.gsub(/^\s+|\s+$/, ""),
        status:               check_capture_status(header),
        description:          description,
        contact_info:         organize_contact_info(tabcontents[1].css('div')),
        offer_terms:          organize_offer_terms(tabcontents[2]),
        offer_note:           tabcontents[2].css('.note').text,
        coockie_duration:     organize_term_options(tabcontents[2], "Cookie Duration:"),
        lock_period:          organize_term_options(tabcontents[2], "Lock Period:"),
        promo_methods:        organize_promo_methods(tabcontents[3]),
        suggested_keywords:   check_capture_keywords(encoding_converter, tabcontents[4], "Suggested Keywords:"),
        restricted_keywords:  restricted_keywords,
        bidding_policy:       check_policy(company_name, description, restricted_keywords)
      )

      scraping_count += 1
      puts "Scraping.. total of #{scraping_count} so far."
    end

    # Console logs for monitoring
    time_finished = Time.now
    seconds_taken = time_finished - time_start
    puts "This rake task has taken #{seconds_taken} secs or #{seconds_taken / 60} minutes."
  end
end

#############################################################################################
# Helper Functions - Organizers
#############################################################################################

def organize_contact_info(raw_object)
  organized_contact = []
  raw_object.each do |div|
    break if div.text.gsub(/^\s+|\s+$/, "") == "Address:"
    organized_contact << div.text.gsub(/^\s+|\s+$/, "").gsub(/\n|\s{2,}/," ")
  end
  organized_contact << "Address: "+ raw_object[-1].text.gsub(/^\s+|\s+$/, "").gsub(/\n|\s{2,}/," ")
end

def organize_offer_terms(raw_object)
  offer_array = []
  if raw_object.css('.pd_left').count != 0
    raw_object.css('.pd_left').count.times do |i|
      offer_array << [raw_object.css('.pd_left')[i].text.gsub(/^\s+|\s+$/, ""),
                      raw_object.css('.pd_right')[i].text.gsub(/^\s+|\s+$/, "")]
    end
  else
    link_to_details = "http://www.pepperjamnetwork.com/" + raw_object.css('.yellow_bld')[0].attributes['href'].value
    offer_array << ["Link for details", link_to_details]
  end
  return offer_array
end

def organize_term_options(raw_object, option_label)
  if raw_object.search("[text()*=\"#{option_label}\"]").count == 0
    return ["", ""]
  else
    option_term = raw_object.search("[text()*=\"#{option_label}\"]").first.parent.next_element.text.gsub(/^\s+|\s+$/, "")
    return [option_label, option_term]
  end
end

def organize_promo_methods(raw_object)
  promo_methods_array = []
  raw_object.css('li').each do |li|
    promo_methods_array << li.text
  end
  return promo_methods_array
end

def check_capture_logo_url(raw_object)
  if raw_object.css('.logo div img').empty?
    return "n/a"
  else
    return raw_object.css('.logo div img').first.attributes['src'].value
  end
end

def check_capture_status(raw_object)
  if raw_object.css('.current-status').empty?
    return "n/a"
  else
    return raw_object.css('.current-status').first.children.first.text.gsub!("Your Status: ", "")
  end
end

def check_capture_keywords(converter_object, raw_object, label_text)
  if raw_object.search("[text()*=\"#{label_text}\"]").empty?
    return "n/a"
  else
    raw_text = raw_object.search("[text()*=\"#{label_text}\"]").first.next.text
    processed_text = converter_object.iconv(raw_text)
    return processed_text.gsub(/^\s+|\s+$/, "")
  end
end


#############################################################################################
# Helper Functions - Scanner
#############################################################################################

# 'check_policy' function will scan the data and categorize the policy into the following categories:
# [:allowed, "direct-pos"]
# [:allowed, "implied-pos"]
# [:prohibited, "strong-neg"]
# [:prohibited, "implied-neg"]

def check_policy(company_name, description, restricted_keywords)

  # Step 1: Direct positive indicator check
  if restricted_keywords.downcase.scan('open search policy').count != 0
    return [:allowed, "direct-pos"]

  # Step 2: Strong negagtive indicator check
  elsif check_strong_neg(description + restricted_keywords) != 0
    return [:prohibited, "strong-neg"]

  # Step 3-A: Implied negagtive indicator check by company name
  elsif restricted_keywords.downcase.scan(company_name.downcase).count != 0
    return [:prohibited, "implied-neg"]

  # Step 3-B: Implied negagtive indicator check by implied negative phrases
  elsif check_implied_neg(description + restricted_keywords) != 0
    return [:prohibited, "implied-neg"]

  # Step 4: Interpret as an implied positive if not caught by none of the above
  else
    return [:allowed, "implied-pos"]
  end
end

def check_strong_neg(text_for_scan)
  detected_indicator = 0
  strong_negatives = ["no tm bidding",
                      "no trade mark bidding",
                      "no trademark bidding",
                      "no keyword bidding",
                      "not allow trademark",
                      "not allow tm bidding",
                      "no kw bidding",
                      "no paid search allowed",
                      "branded keywords bidding is not allowed",
                      "tm bidding is not allowed",
                      "trademark bidding is not allowed",
                      "trademark bidding not allowed",
                      "trademarks or any variation",
                      "tm bidding is prohibited",
                      "tm bidding prohibited",
                      "trademark bidding is prohibited",
                      "trademark bidding prohibited"]

  strong_negatives.each do |neg|
    break if detected_indicator != 0
    detected_indicator += (text_for_scan).downcase.scan(neg).count
  end
  return detected_indicator
end

def check_implied_neg(text_for_scan)
  detected_indicator = 0
  implied_negatives = ["not permitted to bid",
                       "may not bid",
                       "prohibited to bid",
                       "any variation",
                       "misspelling",
                       "including but not limited to"]

  implied_negatives.each do |neg|
    break if detected_indicator != 0
    detected_indicator += (text_for_scan).downcase.scan(neg).count
  end
  return detected_indicator
end



