require 'mechanize'
require 'terminal-table'
require 'ostruct'
require 'recursive-open-struct'
require 'pry'
require 'logger'

class Integer
  def monetize(num, sep = '.', symbol = '$')
    symbol + num.to_s.reverse.scan(/\d{1,3}/).join(sep).reverse
  end
end

module CMR
  class Scraper

    LOGGER = Logger.new(STDOUT)

    attr_accessor :config

    def initialize(config_file)
      parse_config_file config_file
    end

    def parse_config_file(file_path)
      yaml = YAML::load_file(File.join(__dir__, file_path))
      @config = RecursiveOpenStruct.new(yaml)
    end

    def parse_url

      LOGGER.info "Initializing agent"

      agent = Mechanize.new
      parsed_table = {}
      description = Hash.new { |h,k| h[k] = {} }

      LOGGER.info "Agent initialized"

      agent.get(config.target) do |page|
        structure = config.structure

        LOGGER.info "Login starting"

        login_form = page.form_with(id: structure.elements.login_form)
        rut_parts = config.username.gsub(/\./, '').split('-')
        rut_field = login_form.field_with(:name => structure.fields.rut)
        rut_field.value = rut_parts[0].strip
        dig_field = login_form.field_with(:name => structure.fields.digit)
        dig_field.value = rut_parts[1].strip
        pass_field = login_form.field_with(:name => structure.fields.pass)
        pass_field.value = config.password

        agent.submit(login_form)

        LOGGER.info "Parsing summary"
        element_description = agent.page.search(structure.elements.description)

        config.structure.mappings.to_h.each do |k,v|
          text = element_description.search(v).text
          if text.index '$'
            value = text.split("$").map(&:strip)
            description[k] = OpenStruct.new(
              :name => value[0].gsub(/[^\w\s]*/, '').strip,
              :value => value[1].gsub(/\./, '')
            )
          else
            value = text.strip.lines.map(&:strip)
            description[k] = OpenStruct.new(
              :name => value[0],
              :value => value[1]
            )
          end
        end

        binding.pry

        puts Terminal::Table.new(
          :title => "Resumen",
          :headings => description.values.map(&:name),
          :rows => [ description.values.map { |e| e.value.is_a?(Integer) ? e.value.monetize : e.value } ]
        )

        LOGGER.info "Navigating to movements"
        agent.page.link_with(text: /#{structure.elements.movements}/).click

        table = agent.page.search('#table-sorter')
        parsed_table = parse_table table

        LOGGER.info "Loging out"
        agent.page.link_with(href: /#{structure.elements.logout}/).click
      end

      parsed_table
    end

    def parse_table(data)
      rows = []

      headers = data.xpath("//tr").first.xpath(".//*[self::td or self::th]").map(&:text)
      headers = headers[0..-2]

      data.xpath("//tr")[1..-1].map do |tr|
        row = []
        binding.pry
        date = tr.search(".fecha").text
        descr = tr.search(".descripcion span").text.gsub(/\s{2,}/, ' ')
        value = tr.search(".valor-compra").text.gsub(/[\$\.]/, '').to_i
        row << tr.search(".cuotas").text.gsub(/[\$\.]/, '').to_i
        row << tr.search(".valor-cuota").text.gsub(/[\$\.]/, '').to_i
        row << tr.search(".puntos").text.gsub(/[\$\.]/, '').to_i
        rows << [date, descr, value]
      end
      [ headers, rows ]
    end

    def print_summary
      puts summary
    end

    def summary
      headers, rows = parse_url

      Terminal::Table.new(
        :title => "Movimientos",
        :headings => headers,
        :rows => rows
      )
    end
  end
end

p = CMR::Scraper.new ARGV[0]
p.print_summary
