require 'spec_helper'

module Api
  describe OrdersController, type: :controller do
    include AuthenticationWorkflow
    render_views

    let!(:regular_user) { create(:user) }
    let!(:admin_user) { create(:admin_user) }

    let!(:distributor) { create(:distributor_enterprise) }
    let!(:coordinator) { create(:distributor_enterprise) }
    let!(:order_cycle) { create(:simple_order_cycle, coordinator: coordinator) }

    describe '#index' do
      let!(:distributor2) { create(:distributor_enterprise) }
      let!(:coordinator2) { create(:distributor_enterprise) }
      let!(:supplier) { create(:supplier_enterprise) }
      let!(:order_cycle2) { create(:simple_order_cycle, coordinator: coordinator2) }
      let!(:order1) do
        create(:order, order_cycle: order_cycle, state: 'complete', completed_at: Time.zone.now,
                       distributor: distributor, billing_address: create(:address) )
      end
      let!(:order2) do
        create(:order, order_cycle: order_cycle, state: 'complete', completed_at: Time.zone.now,
                       distributor: distributor2, billing_address: create(:address) )
      end
      let!(:order3) do
        create(:order, order_cycle: order_cycle, state: 'complete', completed_at: Time.zone.now,
                       distributor: distributor, billing_address: create(:address) )
      end
      let!(:order4) do
        create(:completed_order_with_fees, order_cycle: order_cycle2, distributor: distributor2)
      end
      let!(:order5) { create(:order, state: 'cart', completed_at: nil) }
      let!(:line_item1) do
        create(:line_item_with_shipment, order: order1,
                                         product: create(:product, supplier: supplier))
      end
      let!(:line_item2) do
        create(:line_item_with_shipment, order: order2,
                                         product: create(:product, supplier: supplier))
      end
      let!(:line_item3) do
        create(:line_item_with_shipment, order: order2,
                                         product: create(:product, supplier: supplier))
      end
      let!(:line_item4) do
        create(:line_item_with_shipment, order: order3,
                                         product: create(:product, supplier: supplier))
      end

      context 'as a regular user' do
        before do
          allow(controller).to receive(:spree_current_user) { regular_user }
          get :index
        end

        it "returns unauthorized" do
          assert_unauthorized!
        end
      end

      context 'as an admin user' do
        before do
          allow(controller).to receive(:spree_current_user) { admin_user }
          get :index
        end

        it "retrieves a list of orders with appropriate attributes,
            including line items with appropriate attributes" do

          returns_orders(json_response)
        end

        it "formats completed_at to 'yyyy-mm-dd hh:mm'" do
          completed_dates = json_response['orders'].map{ |order| order['completed_at'] }
          correct_formats = completed_dates.all?{ |a| a == order1.completed_at.strftime('%B %d, %Y') }

          expect(correct_formats).to be_truthy
        end

        it "returns distributor object with id key" do
          distributors = json_response['orders'].map{ |order| order['distributor'] }
          expect(distributors.all?{ |d| d.key?('id') }).to be_truthy
        end

        it "returns the order number" do
          order_numbers = json_response['orders'].map{ |order| order['number'] }
          expect(order_numbers.all?{ |number| number.match("^R\\d{5,10}$") }).to be_truthy
        end
      end

      context 'as an enterprise user' do
        context 'producer enterprise' do
          before do
            allow(controller).to receive(:spree_current_user) { supplier.owner }
            get :index
          end

          it "does not display line items for which my enterprise is a supplier" do
            assert_unauthorized!
          end
        end

        context 'coordinator enterprise' do
          before do
            allow(controller).to receive(:spree_current_user) { coordinator.owner }
            get :index
          end

          it "retrieves a list of orders" do
            returns_orders(json_response)
          end
        end

        context 'hub enterprise' do
          before do
            allow(controller).to receive(:spree_current_user) { distributor.owner }
            get :index
          end

          it "retrieves a list of orders" do
            returns_orders(json_response)
          end
        end
      end

      context 'using search filters' do
        before do
          allow(controller).to receive(:spree_current_user) { admin_user }
        end

        it 'can show only completed orders' do
          get :index, format: :json, q: { completed_at_not_null: true, s: 'created_at desc' }

          expect(json_response['orders']).to eq serialized_orders([order4, order3, order2, order1])
        end
      end

      context 'with pagination' do
        before do
          allow(controller).to receive(:spree_current_user) { distributor.owner }
        end

        it 'returns pagination data when query params contain :per_page]' do
          get :index, per_page: 15, page: 1

          pagination_data = {
            'results' => 2,
            'pages' => 1,
            'page' => 1,
            'per_page' => 15
          }

          expect(json_response['pagination']).to eq pagination_data
        end
      end
    end

    describe "#show" do
      let!(:order) { create(:completed_order_with_totals, order_cycle: order_cycle, distributor: distributor ) }

      context "Resource not found" do
        before { allow(controller).to receive(:spree_current_user) { admin_user } }

        it "when no order number is given" do
          get :show, id: nil
          expect_resource_not_found
        end

        it "when order number given is not in the systen" do
          get :show, id: "X1321313232"
          expect_resource_not_found
        end

        def expect_resource_not_found
          expect(json_response).to eq( "error" => "The resource you were looking for could not be found." )
          expect(response.status).to eq(404)
        end
      end

      context "access" do
        it "returns unauthorized, as a regular user" do
          allow(controller).to receive(:spree_current_user) { regular_user }
          get :show, id: order.number
          assert_unauthorized!
        end

        it "returns the order, as an admin user" do
          allow(controller).to receive(:spree_current_user) { admin_user }
          get :show, id: order.number
          expect_order
        end

        it "returns the order, as the order distributor owner" do
          allow(controller).to receive(:spree_current_user) { order.distributor.owner }
          get :show, id: order.number
          expect_order
        end

        it "returns unauthorized, as the order product's supplier owner" do
          allow(controller).to receive(:spree_current_user) { order.line_items.first.variant.product.supplier.owner }
          get :show, id: order.number
          assert_unauthorized!
        end

        it "returns the order, as the Order Cycle coorinator owner" do
          allow(controller).to receive(:spree_current_user) { order.order_cycle.coordinator.owner }
          get :show, id: order.number
          expect_order
        end
      end

      context "as distributor owner" do
        let!(:order) { create(:completed_order_with_fees, order_cycle: order_cycle, distributor: distributor ) }

        before { allow(controller).to receive(:spree_current_user) { order.distributor.owner } }

        it "can view an order not in a standard state" do
          order.update_attributes(completed_at: nil, state: 'shipped')
          get :show, id: order.number
          expect_order
        end

        it "returns an order with all required fields" do
          get :show, id: order.number
          expect_order
          expect_detailed_attributes_to_be_present(json_response)

          expect(json_response[:bill_address][:address1]).to eq(order.bill_address.address1)
          expect(json_response[:bill_address][:lastname]).to eq(order.bill_address.lastname)
          expect(json_response[:ship_address][:address1]).to eq(order.ship_address.address1)
          expect(json_response[:ship_address][:lastname]).to eq(order.ship_address.lastname)
          expect(json_response[:shipping_method][:name]).to eq(order.shipping_method.name)
          json_response[:adjustments].each do |adjustment|
            if adjustment[:label] == "Transaction fee"
              expect(adjustment[:amount]).to eq(order.adjustments.payment_fee.first.amount.to_s)
            elsif json_response[:adjustments].first[:label] == "Shipping"
              expect(adjustment[:amount]).to eq(order.adjustments.shipping.first.amount.to_s)
            end
          end
          expect(json_response[:payments].first[:amount]).to eq(order.payments.first.amount.to_s)
          expect(json_response[:line_items].size).to eq(order.line_items.size)
          expect(json_response[:line_items].first[:variant][:product_name]). to eq(order.line_items.first.variant.product.name)
        end
      end

      def expect_order
        expect(response.status).to eq 200
        expect_correct_order(json_response, order)
      end

      def expect_correct_order(json_response, order)
        expect(json_response[:number]).to eq(order.number)
        expect(json_response[:email]).to eq(order.email)
      end

      def expect_detailed_attributes_to_be_present(json_response)
        expect(order_detailed_attributes.all?{ |attr| json_response.key? attr.to_s }).to eq(true)
      end
    end

    private

    def serialized_orders(orders)
      serialized_orders = ActiveModel::ArraySerializer.new(
        orders,
        each_serializer: Api::Admin::OrderSerializer,
        root: false
      )

      JSON.parse(serialized_orders.to_json)
    end

    def returns_orders(response)
      keys = response['orders'].first.keys.map(&:to_sym)
      expect(order_attributes.all?{ |attr| keys.include? attr }).to be_truthy
    end

    def order_attributes
      [
        :id, :number, :full_name, :email, :phone, :completed_at, :display_total,
        :edit_path, :state, :payment_state, :shipment_state,
        :payments_path, :ship_path, :ready_to_ship, :created_at,
        :distributor_name, :special_instructions, :payment_capture_path
      ]
    end

    def order_detailed_attributes
      [
        :number, :item_total, :total, :state, :adjustment_total, :payment_total,
        :completed_at, :shipment_state, :payment_state, :email, :special_instructions,
        :adjustments, :payments, :bill_address, :ship_address, :line_items, :shipping_method
      ]
    end
  end
end
