require 'csv'

namespace :scraper do
  desc "Scrape pepperjamnetwork.com for program info and scan for bidding policy"
  task pepperjam: :environment do

    # Initiate a Mechanize object, request for pepperjam site and log in with credentials.
    agent = Mechanize.new
    target_host = 'http://www.pepperjamnetwork.com/'
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
    time_start = Time.now

    prgm_page = agent.get("#{target_host}/affiliate/program/popup?programId=#{prgm_ids_array[0]}")
    desc_page = agent.get("#{target_host}/affiliate/program/description?programId=#{prgm_ids_array[0]}")
    header = prgm_page.search('.program-header')
    tabcontents = prgm_page.search('.tab-content')

    puts prgm_id =              prgm_ids_array[0]
    puts company_name =         header.css('.program-name').text.gsub(/^\s+|\s+$/, "")
    puts logo_img =             header.css('.logo div img').first.attributes['src'].value
    puts site_address =         header.css('.websiteurl').text()
    puts categories =           header.css('.base-info div')[1].children[2].text.gsub(/^\s+|\s+$/, "")
    puts mobile_tracking =      header.css('.base-info div')[2].children[2].text.gsub(/^\s+|\s+$/, "")
    puts status =               header.css('.current-status').first.children.first.text.gsub!("Your Status: ", "")
    puts description =          desc_page.search('span').first.text
    puts contact_info =         organize_contact_info(tabcontents[1].css('div'))
    puts offer_terms =          organize_offer_terms(tabcontents[2])
    puts offer_note =           tabcontents[2].css('.note').text
    puts coockie_duration =     organize_term_options(tabcontents[2], 0, 1)
    puts lock_period =          organize_term_options(tabcontents[2], 2, 3)
    puts promo_methods =        organize_promo_methods(tabcontents[3])
    puts suggested_keywords =   tabcontents[4].children[2].text.gsub(/^\s+|\s+$/, "")
    puts restricted_keywords =  tabcontents[4].children[4].text.gsub(/^\s+|\s+$/, "")
    puts bidding_policy =       check_policy(company_name, description, restricted_keywords)

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
  raw_object.css('.pd_left').count.times do |i|
    offer_array << [raw_object.css('.pd_left')[i].text.gsub(/^\s+|\s+$/, ""),
                    raw_object.css('.pd_right')[i].text.gsub(/^\s+|\s+$/, "")]
  end
  return offer_array
end

def organize_term_options(raw_object, option_div_index, term_div_index)
  term_options_array = [raw_object.css('.pd_block')[1].css('div')[option_div_index].text.gsub(/^\s+|\s+$/, ""),
                        raw_object.css('.pd_block')[1].css('div')[term_div_index].text.gsub(/^\s+|\s+$/, "")]
  return term_options_array
end

def organize_promo_methods(raw_object)
  promo_methods_array = []
  raw_object.css('li').each do |li|
    promo_methods_array << li.text
  end
  return promo_methods_array
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
    return [:prohibited, "implied-pos"]
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
