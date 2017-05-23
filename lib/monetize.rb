module Extensions
  module Integer
    module Money
      def monetize(sep = '.', symbol = '$')
        symbol + self.to_s.reverse.scan(/\d{1,3}/).join(sep).reverse
      end
    end
  end
end

Integer.include Extensions::Integer::Money
