require 'json'
require 'pry'
require 'termextractor'

class ExtractPatterns
  def initialize(input, fields, match_name)
    @input = JSON.parse(input)
    @fields = fields
    @match_name = match_name
    @output = Array.new
  end

  # Split to find matches
  def comma_list_matches(value)
    if value
      # Split on commas
      list_items = value.split(",")

      # Only get items under certain num of words
      list_items.reject!{ |item| item.split(" ").length > 2 }

      # Clean whitespace and ands
      return list_items.map { |match| match.gsub(" and", "").gsub("and ", "").gsub(".", "").strip.lstrip }
    end
    return []
  end

  # Get words in ALLCAPS past certain length
  def get_allcaps(value, length)
    if length && value
      # Get all matches
      matches = value.scan(/\b(?:[A-Z]|\s){#{length},}\b/)
      
      # Remove matches that are too long
      matches.reject!{|match| match.length > 100}
      
      # Remove whitespace
      return matches.map{ |match| match.strip.lstrip }
    end
    return []
  end

  # Extract set terms
  def find_known_terms(item, field, extract_list)
    d = TermExtractor.new(fixEncode(JSON.pretty_generate([item])), [field], "extracted_codewords")
    d.extractSetTerms(fixEncode(File.read(extract_list)), ["codeword"], "case_sensitive")
    return JSON.parse(d.getAllOutput).first["extracted_codewords"]
  end

  # Fix encoding errors
  def fixEncode(str)
    if str.is_a?(String)
      return str.unpack('C*').pack('U*')
    else
      return str
    end
  end

  # Normalize and match synonyms and deduplicate
  def normalize_results(extracted_raw, synonym_list)
    synonyms = JSON.parse(File.read(synonym_list))
    outarr = extracted_raw.dup

    # Go through all extracted
    extracted_raw.each do |extracted|
      # Go through each item in synonym list
      synonyms.each do |key, value|
        value["codeword"].each do |word|
          # Match found!
          if word.downcase == extracted.downcase
            outarr.delete(extracted)
            outarr.push(key)
          end
        end
      end
    end

    # Return deduplicated
    return outarr.uniq
  end

  # Go through all items in JSON and fields to search
  def search_fields(allcaps_length, extract_list, merge_field)
    # Extract from each item
    @input.each do |item|
      item[@match_name] = Array.new
      
      @fields.each do |field|
        # Extract list results, allcaps, and known codewords from each field
        list_results = comma_list_matches(fixEncode(item[field]))
        allcaps_results = get_allcaps(fixEncode(item[field]), allcaps_length)
        merge_results = item[merge_field] ? item[merge_field] : []
        #known_terms_results = find_known_terms(fixEncode(item), field, extract_list)
                             
        # Merge results and post-process
        item[@match_name] = item[@match_name] | normalize_results((allcaps_results | list_results | merge_results ),extract_list)
      end
      
      # Push updated item out
      @output.push(item)
    end

    return @output
  end

  # Return a ranked hash of the results
  def ranked_hash_output(results)
    # Make array of all results
    allmatches = Array.new
    results.each do |i|
      i["tools_mentioned"].each do |match|
        allmatches.push(match)
      end
    end

    # Make ranked hash
    rankedhash = Hash.new
    allmatches.each do |match|
      if rankedhash[match]
        rankedhash[match] += 1
      else
        rankedhash[match] = 1
      end
    end
    return rankedhash.sort_by{|k, v| v}
  end
end

#dir = "/home/shidash/Data/unknown_test"
#overalloutput = Array.new
#Dir.foreach(dir) do |file|
#  next if file == '.' or file == '..'
#  if !File.directory?(dir+"/"+file) && file.include?(".json") && !file.include?(".json.gpg")
#    e = ExtractPatterns.new(File.read(dir+"/"+file), ["additional_info", "job_description", "skills", "summary"], "tools_mentioned")
#    results = e.search_fields(6, "extract_list.json", nil)
#    File.write(file.gsub(".json", "_extracted.json"), JSON.pretty_generate(results))
#    overalloutput.concat(results)
#  end
#end

#e = ExtractPatterns.new(File.read("blackfin.json"), ["description", "summary"], "tools_mentioned")
#puts e.search_fields(6, "extract_list.json", "skills")
#puts e.ranked_hash_output(overalloutput)
