# frozen_string_literal: true

require "spec_helper"

module ToXMLWithNamespaces
  #
  # Similar example as the to_xml but this time with namespacing
  #
  class Address
    include HappyMapper

    register_namespace "address", "http://www.company.com/address"
    register_namespace "country", "http://www.company.com/country"

    tag "Address"
    namespace "address"

    element :country, "Country", tag: "country", namespace: "country"

    attribute :location, String, on_save: :when_saving_location

    element :street, String
    element :postcode, String
    element :city, String

    element :housenumber, String

    #
    # to_xml will default to the attr_accessor method and not the attribute,
    # allowing for that to be overwritten
    #
    remove_method :housenumber

    def housenumber
      "[#{@housenumber}]"
    end

    def when_saving_location(loc)
      "#{loc}-live"
    end

    #
    # Write a empty element even if this is not specified
    #
    element :description, String, state_when_nil: true

    #
    # Perform the on_save operation when saving
    #
    has_one :date_created, Time,
            on_save: ->(time) { Time.parse(time).strftime("%T %D") if time }

    #
    # Write multiple elements and call on_save when saving
    #
    has_many :dates_updated, Time, on_save: lambda { |times|
      times.compact.map { |time| Time.parse(time).strftime("%T %D") } if times
    }

    #
    # Class composition
    #

    def initialize(parameters)
      parameters.each_pair do |property, value|
        send("#{property}=", value) if respond_to?("#{property}=")
      end
    end
  end

  #
  # Country is composed above the in Address class. Here is a demonstration
  # of how to_xml will handle class composition as well as utilizing the tag
  # value.
  #
  class Country
    include HappyMapper

    register_namespace "countryName", "http://www.company.com/countryName"

    attribute :code, String, tag: "countryCode"
    has_one :name, String, tag: "countryName", namespace: "countryName",
                           state_when_nil: true

    def initialize(parameters)
      parameters.each_pair do |property, value|
        send("#{property}=", value) if respond_to?("#{property}=")
      end
    end
  end

  #
  # This class is an example of a class that has a default namespace
  # xmlns="urn:eventis:prodis:onlineapi:1.0"
  # xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  # xmlns:xsd="http://www.w3.org/2001/XMLSchema"
  #
  class Recipe
    include HappyMapper

    # this is the default namespace of the document
    register_namespace "xmlns", "urn:eventis:prodis:onlineapi:1.0"
    register_namespace "xsi", "http://www.w3.org/2001/XMLSchema-instance"
    register_namespace "xsd", "http://www.w3.org/2001/XMLSchema"

    has_many :ingredients, String

    def initialize(parameters)
      parameters.each_pair do |property, value|
        send("#{property}=", value) if respond_to?("#{property}=")
      end
    end
  end
end

module CoffeeMaking
  class Beverage
    include HappyMapper
    namespace "coffee"

    attribute :name, String
  end

  class CoffeeMachine
    include HappyMapper
    register_namespace "coffee", "http://coffee.org/Coffee/0.1"
    register_namespace "beverage", "http://beverages.org/Beverage/0.1"

    element :beverage, "beverage", namespace: "beverage"
  end
end

RSpec.describe "Saving #to_xml with xml namespaces" do
  context "with namespaces" do
    let(:xml) do
      country = ToXMLWithNamespaces::Country.new(name: "USA", code: "us")
      address = ToXMLWithNamespaces::Address.new("street" => "Mockingbird Lane",
                                                 "location" => "Home",
                                                 "housenumber" => "1313",
                                                 "postcode" => "98103",
                                                 "city" => "Seattle",
                                                 "country" => country,
                                                 "date_created" => "2011-01-01 15:00:00")

      address.dates_updated = ["2011-01-01 16:01:00", "2011-01-02 11:30:01"]

      Nokogiri::XML(address.to_xml).root
    end

    it "sets the namespace specified in the class" do
      expect(xml.xpath("/").children.first.namespace.prefix).to eq "address"
    end

    it "saves elements" do
      elements = { "street" => "Mockingbird Lane", "postcode" => "98103",
                   "city" => "Seattle" }

      elements.each_pair do |property, value|
        expect(xml.xpath("address:#{property}").text).to eq value
      end
    end

    it "saves attributes" do
      expect(xml.xpath("@location").text).to eq "Home-live"
    end

    context "when a scalar element is nil and has state_when_nil: true" do
      it "saves an empty element" do
        nodeset = xml.xpath("address:description")
        aggregate_failures do
          expect(nodeset).not_to be_empty
          expect(nodeset.text).to eq ""
        end
      end
    end

    context "when a scalar element is nil and does not have state_when_nil: true" do
      let(:xml) do
        address = ToXMLWithNamespaces::Address.new("street" => "Mockingbird Lane",
                                                   "location" => nil)
        Nokogiri::XML(address.to_xml).root
      end

      it "saves no element" do
        nodeset = xml.xpath("address:location")
        expect(nodeset).to be_empty
      end
    end

    context \
      "when a scalar element with its own namespace is nil and has state_when_nil: true" do
      let(:xml) do
        country = ToXMLWithNamespaces::Country.new(name: nil, code: "us")
        address = ToXMLWithNamespaces::Address.new(street: "Mockingbird Lane",
                                                   country: country)

        Nokogiri::XML(address.to_xml).root
      end

      it "saves an empty element with the correct namespace" do
        nodeset = xml.xpath("country:country/countryName:countryName")
        aggregate_failures do
          expect(nodeset).not_to be_empty
          expect(nodeset.text).to eq ""
        end
      end
    end

    context "when an element has a custom reader method" do
      it "saves the element with the result of the method call" do
        expect(xml.xpath("address:housenumber").text).to eq "[1313]"
      end
    end

    context "when an element has a 'on_save' parameter" do
      context "with a lambda" do
        it "saves the results" do
          expect(xml.xpath("address:date_created").text).to eq "15:00:00 01/01/11"
        end
      end
    end

    context "when an attribute has a 'on_save' parameter" do
      context "with a lambda" do
        it "saves the result" do
          expect(xml.xpath("@location").text).to eq "Home-live"
        end
      end
    end

    context "when a has_many has a 'on_save' parameter" do
      context "with a lambda" do
        it "saves the result" do
          dates_updated = xml.xpath("address:dates_updated")

          aggregate_failures do
            expect(dates_updated.length).to eq 2
            expect(dates_updated.first.text).to eq "16:01:00 01/01/11"
            expect(dates_updated.last.text).to eq "11:30:01 01/02/11"
          end
        end
      end
    end

    context "when an element type is a HappyMapper subclass" do
      it "saves attributes" do
        expect(xml.xpath("country:country/@countryCode").text).to eq "us"
      end

      it "saves elements" do
        expect(xml.xpath("country:country/countryName:countryName").text).to eq "USA"
      end
    end
  end

  context "with a default namespace" do
    it "writes the default namespace to xml without repeating xmlns" do
      recipe = ToXMLWithNamespaces::Recipe.new(ingredients: ["One Cup Flour",
                                                             "Two Scoops of Lovin"])
      expect(recipe.to_xml).to match(/xmlns="urn:eventis:prodis:onlineapi:1\.0"/)
    end
  end

  context "with namespace supplied by element declaration and by element class" do
    let(:expected_xml) do
      <<~XML
        <?xml version="1.0"?>
        <coffeemachine xmlns:beverage="http://beverages.org/Beverage/0.1" xmlns:coffee="http://coffee.org/Coffee/0.1">
          <beverage:beverage name="coffee"/>
        </coffeemachine>
      XML
    end

    it "uses the element declaration namespace on the element" do
      machine = CoffeeMaking::CoffeeMachine.new
      machine.beverage = CoffeeMaking::Beverage.new.tap { |obj| obj.name = "coffee" }
      expect(machine.to_xml).to eq(expected_xml)
    end
  end
end
