$: << '.'
require 'mechanize'
require 'terminal-table'
require 'ostruct'
require 'recursive-open-struct'
require 'pry'
require 'logger'
require 'lib/monetize'

module CMR
  class Scraper

    LOGGER = Logger.new(STDOUT)

    class << self
      def print_summary(config_file)
        Scraper.new(config_file).print_summary
      end
    end

    attr_accessor :config

    def initialize(config_file)
      parse_config_file config_file
    end

    def parse_config_file(file_path)
      yaml = YAML::load_file(File.join(__dir__, file_path))
      @config = RecursiveOpenStruct.new(yaml)
    end

    def parse_url

      LOGGER.info 'Initializing agent'

      agent = Mechanize.new
      parsed_table = {}
      description = Hash.new { |h,k| h[k] = {} }

      agent.get(config.target) do |page|
        structure = config.structure

        LOGGER.info 'Authentication starting'

        login_form = page.form_with(id: structure.elements.login_form)
        rut_parts = config.username.gsub(/\./, '').split('-')
        rut_field = login_form.field_with(:name => structure.fields.rut)
        rut_field.value = rut_parts[0].strip
        dig_field = login_form.field_with(:name => structure.fields.digit)
        dig_field.value = rut_parts[1].strip
        pass_field = login_form.field_with(:name => structure.fields.pass)
        pass_field.value = config.password

        agent.submit(login_form)

        LOGGER.info 'Parsing summary'
        element_description = agent.page.search(structure.elements.description)

        config.structure.mappings.to_h.each do |k,v|
          text = element_description.search(v).text

          if text.index '$'
            value = text.split('$').map(&:strip)
            description[k] = OpenStruct.new(
              :name => value[0].gsub(/[^\w\s]*/, '').strip,
              :value => value[1].gsub(/\./, '').to_i
            )
          else
            value = text.strip.lines.map(&:strip)
            description[k] = OpenStruct.new(
              :name => value[0],
              :value => value[1]
            )
          end
        end

        LOGGER.info 'Navigating to movements'
        agent.page.link_with(text: /#{structure.elements.movements}/).click

        table = agent.page.search('#table-sorter')
        parsed_table = parse_table table

        LOGGER.info 'Closing session'
        agent.page.link_with(href: /#{structure.elements.logout}/).click
      end

      OpenStruct.new(:description => description, :movements => parsed_table)
    end

    def parse_table(data)
      rows = []

      headers = data.xpath("//tr").first.xpath(".//*[self::td or self::th]").map(&:text)
      headers = headers[0..-2]

      data.xpath("//tr")[1..-1].map do |tr|
        date = tr.search(".fecha").text
        descr = tr.search(".descripcion .detalle-tabla .title").text.gsub(/\s{2,}/, ' ')
        if tr.search('.descripcion .pendiente').size > 0 then descr << ' (*)' end
        value = tr.search(".valor-compra").text.gsub(/[\$\.]/, '').to_i
        payments = tr.search(".cuotas").text.gsub(/[\$\.]/, '').to_i
        val_payments = tr.search(".valor-cuota").text.gsub(/[\$\.]/, '').to_i
        points = tr.search(".puntos").text.gsub(/[\$\.]/, '').to_i
        rows << [date, descr, value.monetize, payments, val_payments.monetize, points]
      end
      [ headers, rows ]
    end

    def print_summary
      parsed_url = parse_url
      description = parsed_url.description

      movims = Terminal::Table.new(
        :title => 'Movimientos',
        :headings => parsed_url.movements[0],
        :rows => parsed_url.movements[1]
      )

      resumen = Terminal::Table.new do |t|
        t.title = 'Resumen'
        t << description.values.map(&:name)
        t << description.values.map { |e|
          e.value.is_a?(Numeric) ? e.value.monetize : e.value
        }
      end

      puts resumen
      puts movims

    end
  end
end

CMR::Scraper.print_summary(ARGV[0])
