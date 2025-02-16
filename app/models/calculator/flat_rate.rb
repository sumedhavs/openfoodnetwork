# frozen_string_literal: false

require 'spree/localized_number'

module Calculator
  class FlatRate < Spree::Calculator
    extend Spree::LocalizedNumber

    preference :amount, :decimal, default: 0

    localize_number :preferred_amount

    def self.description
      I18n.t(:flat_rate_per_order)
    end

    def compute(_object = nil)
      preferred_amount
    end
  end
end
