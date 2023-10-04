require "open-uri"
require "htmlentities"

module Oddb2xml
  FAKE_GTIN_START = "999999"
  def self.gen_prodno(iksnr, seqnr)
    sprintf("%05d", iksnr) + sprintf("%02d", seqnr)
  end

  def self.uri_open(url)
    version = RUBY_VERSION.split(".").map { |x| x.to_i }
    if (version <=> [2, 5, 0]) >= 0
      URI.parse(url).open
    else
      IO.popen(url)
    end
  end

  def self.calc_checksum(str)
    str = str.strip
    sum = 0
    val = str.split(//u)
    12.times do |idx|
      fct = ((idx % 2) * 2) + 1
      sum += fct * val[idx].to_i
    end
    ((10 - (sum % 10)) % 10).to_s
  end

  unless defined?(RSpec)
    WORK_DIR = Dir.pwd
    DOWNLOADS = "#{Dir.pwd}/downloads"
  end
  @options = {}
  @atc_csv_origin = "https://github.com/zdavatz/cpp2sqlite/blob/master/input/atc_codes_multi_lingual.txt"
  @atc_csv_content = {}

  def self.html_decode(string)
    german = string
    german = string.force_encoding("ISO-8859-1").encode("UTF-8") if string.encoding.to_s.eql?("ASCII")
    until german.eql?(HTMLEntities.new.decode(german))
      german = HTMLEntities.new.decode(german)
    end
    Oddb2xml.patch_some_utf8(german).gsub("<br>", "\n")
  end

  def self.patch_some_utf8(line)
    begin
      line = line.encode("utf-8")
    rescue
    end
    begin
      line.tr("\u0089", "‰").tr("\u0092", "’").tr("\u0096", "-").tr("\u2013", "-").tr("\u201D", '"').chomp
    rescue => error
      puts "#{error}: in #{line}"
      line
    end
  end

  def self.convert_to_8859_1(line)
    # We want to ignore lines which are not really UTF-8 encoded
    ausgabe = Oddb2xml.patch_some_utf8(line).encode("ISO-8859-1")
    ausgabe.encode("ISO-8859-1")
  rescue => error
    puts "#{error}: in #{line}"
  end

  def self.add_epha_changes_for_ATC(iksnr, atc_code, force_run: false)
    @atc_csv_content = {} if force_run
    if @atc_csv_content.size == 0
      Oddb2xml.uri_open(@atc_csv_origin).readlines.each { |line|
        items = line.split(",")
        @atc_csv_content[[items[0], items[1]]] = items[2]
      }

    end
    new_value = @atc_csv_content[[iksnr.to_s, atc_code]]
    new_value || atc_code
  end

  def self.log(msg)
    return unless @options[:log]
    # TODO:: require 'pry'; binding.pry if msg.size > 1000
    $stdout.puts "#{Time.now.strftime("%Y-%m-%d %H:%M:%S")}: #{msg[0..250]}"
    $stdout.flush
  end

  def self.save_options(options)
    @options = options
  end

  def self.skip_download?
    @options[:skip_download]
  end

  def self.skip_download(file)
    return false if defined?(VCR)
    dest = "#{DOWNLOADS}/#{File.basename(file)}"
    if File.exist?(dest)
      FileUtils.cp(dest, file, verbose: false, preserve: true) unless File.expand_path(file).eql?(dest)
      return true
    end
    false
  end

  def self.download_finished(file, remove_file = true)
    src = "#{WORK_DIR}/#{File.basename(file)}"
    dest = "#{DOWNLOADS}/#{File.basename(file)}"
    FileUtils.makedirs(DOWNLOADS)
    # return unless File.exist?(file)
    return unless file && File.exist?(file)
    return if File.expand_path(file).eql?(dest)
    FileUtils.cp(src, dest, verbose: false)
    Oddb2xml.log("download_finished saved as #{dest} #{File.size(dest)} bytes.")
  end

  # please keep this constant in sync between (GEM) swissmedic-diff/lib/swissmedic-diff.rb and (GEM) oddb2xml/lib/oddb2xml/extractor.rb
  def self.check_column_indices(sheet)
    row = sheet[5] # Headers are found at row 5 since February 5

    error_2019 = nil
    0.upto(COLUMNS_FEBRUARY_2019.size - 1).each { |idx| puts "#{idx}: #{row[idx].value}" } if $VERBOSE
    COLUMNS_FEBRUARY_2019.each { |key, value|
      header_name = row[COLUMNS_FEBRUARY_2019.keys.index(key)].value.to_s
      unless value.match(header_name)
        puts "#{__LINE__}: #{key} ->  #{COLUMNS_FEBRUARY_2019.keys.index(key)} #{value}\nbut was  #{header_name}" if $VERBOSE
        error_2019 = "Packungen.xlslx_has_unexpected_column_#{COLUMNS_FEBRUARY_2019.keys.index(key)}_#{key}_#{value}_but_was_#{header_name}"
        # require 'pry'; binding.pry
        break
      end
    }
    raise error_2019.to_s if error_2019
  end

  # please keep this constant in sync between (GEM) swissmedic-diff/lib/swissmedic-diff.rb and (GEM) oddb2xml/lib/oddb2xml/extractor.rb
  COLUMNS_FEBRUARY_2019 = {
    iksnr: /Zulassungs-Nummer/i, # column-nr: 0
    seqnr: /Dosisstärke-nummer/i,
    name_base: /Bezeichnung des Arzneimittels/i,
    company: /Zulassungsinhaberin/i,
    production_science: /Heilmittelcode/i,
    index_therapeuticus: /IT-Nummer/i, # column-nr: 5
    atc_class: /ATC-Code/i,
    registration_date: /Erstzul.datum Arzneimittel/i,
    sequence_date: /Zul.datum Dosisstärke/i,
    expiry_date: /Gültigkeitsdauer der Zulassung/i,
    ikscd: /Packungscode/i, # column-nr: 10
    size: /Packungsgrösse/i,
    unit: /Einheit/i,
    ikscat: /Abgabekategorie Packung/i,
    ikscat_seq: /Abgabekategorie Dosisstärke/i,
    ikscat_preparation: /Abgabekategorie Arzneimittel/i, # column-nr: 15
    substances: /Wirkstoff/i,
    composition: /Zusammensetzung/i,
    composition_AMZV: /Volldeklaration rev. AMZV umgesetzt/i,
    indication_registration: /Anwendungsgebiet Arzneimittel/i,
    indication_sequence: /Anwendungsgebiet Dosisstärke/i, # column-nr 20
    gen_production: /Gentechnisch hergestellte Wirkstoffe/i,
    insulin_category: /Kategorie bei Insulinen/i,
    # swissmedi corrected in february 2018 the typo  betäubunsmittel to  betäubungsmittel-
    drug_index: /Verz. bei betäubungsmittel-haltigen Arzneimittel/i
  }

  COLUMNS_JULY_2015 = {
    iksnr: /Zulassungs-Nummer/i, # column-nr: 0
    seqnr: /Dosisstärke-nummer/i,
    name_base: /Präparatebezeichnung/i,
    company: /Zulassungsinhaberin/i,
    production_science: /Heilmittelcode/i,
    index_therapeuticus: /IT-Nummer/i, # column-nr: 5
    atc_class: /ATC-Code/i,
    registration_date: /Erstzulassungs-datum./i,
    sequence_date: /Zul.datum Dosisstärke/i,
    expiry_date: /Gültigkeitsdauer der Zulassung/i,
    ikscd: /Packungscode/i, # column-nr: 10
    size: /Packungsgrösse/i,
    unit: /Einheit/i,
    ikscat: /Abgabekategorie Arzneimittel/i,
    ikscat_seq: /Abgabekategorie Dosisstärke/i,
    ikscat_preparation: /Abgabekategorie Präparat/i, # column-nr: 15
    substances: /Wirkstoff/i,
    composition: /Zusammensetzung/i,
    indication_registration: /Anwendungsgebiet Präparat/i,
    indication_sequence: /Anwendungsgebiet Dosisstärke/i,
    gen_production: /Gentechnisch hergestellte Wirkstoffe/i, # column-nr 20
    insulin_category: /Kategorie bei Insulinen/i,
    # swissmedi corrected in february 2018 the typo  betäubunsmittel to  betäubungsmittel-
    drug_index: /Verz. bei betäubun.*smittel-haltigen Präparaten/i
  }
  def self.add_hash(string)
    doc = Nokogiri::XML.parse(string) do |config|
      config.huge
    end
    nr = 0
    doc.root.elements.each do |node|
      nr += 1
      next if node.name.eql?("RESULT")
      node["SHA256"] = Digest::SHA256.hexdigest node.text
    end
    doc.to_xml
  end

  def self.verify_sha256(file)
    f = File.open(file)
    doc = Nokogiri::XML(f)
    nr = 0
    doc.root.elements.each do |node|
      nr += 1
      next if node.name.eql?("RESULT")
      sha256 = Digest::SHA256.hexdigest node.text
      unless node["SHA256"].eql?(sha256)
        puts "Verifiying #{node["SHA256"]} != expectd #{sha256} against node #{node.text} failed"
        exit(3)
      end
    end
    true
  end

  def self.validate_via_xsd(xsd_file, xml_file)
    xsd = IO.open(xsd_file).read
    xsd_rtikelstamm_xml = Nokogiri::XML::Schema(xsd)
    doc = Nokogiri::XML(File.read(xml_file))
    xsd_rtikelstamm_xml.validate(doc).each do |error|
      if error.message
        puts "Failed validating #{xml_file} with #{File.size(xml_file)} bytes using XSD from #{xsd_file}"
        puts "CMD: xmllint --noout --schema #{xsd_file} #{xml_file}"
      end
      msg = "expected #{error.message} to be nil\nfor #{xml_file}"
      puts msg
      expect(error.message).to be_nil, msg
    end
  end

  # Needed for ensuring consistency for the Artikelstamm
  @@prodno_to_ean13 = {}
  @@no8_to_ean13 = {}
  @@ean13_to_prodno = {}
  @@ean13_to_no8 = {}
  def self.setEan13forProdno(prodno, ean13)
    if ean13.to_i == 7680006660045 || ean13.to_i == 7680006660014
      Oddb2xml.log "setEan13forProdno #{prodno} ean13 #{ean13}"
    end
    @@prodno_to_ean13[prodno] ||= []
    @@prodno_to_ean13[prodno] << ean13
    @@ean13_to_prodno[ean13] = prodno
  end

  def self.setEan13forNo8(no8, ean13)
    if ean13.to_i == 7680006660045 || ean13.to_i == 7680006660014
      Oddb2xml.log "setEan13forNo8 #{no8} ean13 #{ean13}"
    end
    if @@no8_to_ean13[no8].nil?
      @@no8_to_ean13[no8] = ean13
      @@ean13_to_no8[ean13] = no8
    elsif !@@no8_to_ean13[no8].eql?(ean13)
      Oddb2xml.log "@@no8_to_ean13[no8] #{@@no8_to_ean13[no8]} not overridden by #{ean13}"
    end
  end

  def self.getEan13forProdno(prodno)
    @@prodno_to_ean13[prodno] || []
  end

  def self.getEan13forNo8(no8)
    @@no8_to_ean13[no8] || []
  end

  def self.getProdnoForEan13(ean13)
    @@ean13_to_prodno[ean13]
  end

  def self.getNo8ForEan13(ean13)
    @@ean13_to_no8[ean13]
  end
end
