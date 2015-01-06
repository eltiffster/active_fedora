require 'spec_helper'

describe ActiveFedora::NtriplesRDFDatastream do
  before do
    class MyDatastream < ActiveFedora::NtriplesRDFDatastream
      map_predicates do |map|
        map.title(:in => RDF::DC) do |index|
          index.as :searchable, :facetable, :displayable
        end
        map.date_uploaded(:to => "dateSubmitted", :in => RDF::DC) do |index|
          index.type :date
          index.as :searchable, :displayable, :sortable
        end
        map.part(:to => "hasPart", :in => RDF::DC)
        map.based_near(:in => RDF::FOAF)
        map.related_url(:to => "seeAlso", :in => RDF::RDFS)
      end
    end
    class RdfTest < ActiveFedora::Base
      has_metadata :name=>'rdf', :type=>MyDatastream
      delegate_to 'rdf', [:based_near, :related_url, :part, :date_uploaded]
      delegate :title, :to=>'rdf', :unique=>true
    end
    @subject = RdfTest.new
  end

  subject {
    @subject
  }

  after do
    Object.send(:remove_const, :RdfTest)
    Object.send(:remove_const, :MyDatastream)
  end

  it "should not try to send an empty datastream" do
    @subject.save
  end

  it "should save content properly upon save" do
    foo = RdfTest.new(:pid=>'test:1') #Pid needs to match the subject in the loaded file
    foo.title = 'Hamlet'
    foo.save
    expect(foo.title).to eq('Hamlet')
    foo.rdf.content = File.new('spec/fixtures/mixed_rdf_descMetadata.nt').read
    foo.save
    expect(foo.title).to eq('Title of work')
  end

  it "should delegate as_json to the fields" do
    @subject = RdfTest.new(title: "Title of work")
    expect(@subject.rdf.title.as_json).to eq(["Title of work"])
    expect(@subject.rdf.title.to_json).to eq("\[\"Title of work\"\]")
  end

  it "should solrize even when the object is not new" do
    foo = RdfTest.new
    expect(foo).to receive(:update_index).once
    foo.title = "title1"
    foo.save
    foo = RdfTest.find(foo.pid)
    expect(foo).to receive(:update_index).once
    foo.title = "The Work2"
    foo.save
  end

  it "should serialize dates" do
    subject.date_uploaded = Date.parse('2012-11-02')
    expect(subject.date_uploaded.first).to be_kind_of Date
    solr_document = subject.to_solr
    expect(solr_document[ActiveFedora::SolrService.solr_name('rdf__date_uploaded', :date, :searchable)]).to eq(['2012-11-02T00:00:00Z'])
  end

  it "should produce a solr document" do
    @subject = RdfTest.new(title: "War and Peace")
    solr_document = @subject.to_solr
    expect(solr_document[ActiveFedora::SolrService.solr_name('rdf__title', :string, :displayable)]).to eq(["War and Peace"])
    expect(solr_document[ActiveFedora::SolrService.solr_name('rdf__title', :string, :facetable)]).to eq(["War and Peace"])
    expect(solr_document[ActiveFedora::SolrService.solr_name('rdf__title', :string, :searchable)]).to eq(["War and Peace"])
  end

  it "should set and recall values" do
    @subject.title = 'War and Peace'
    expect(@subject.rdf).to be_changed
    @subject.based_near = "Moscow, Russia"
    @subject.related_url = "http://en.wikipedia.org/wiki/War_and_Peace"
    @subject.part = "this is a part"
    @subject.save
    expect(@subject.title).to eq('War and Peace')
    expect(@subject.based_near).to eq(["Moscow, Russia"])
    expect(@subject.related_url).to eq(["http://en.wikipedia.org/wiki/War_and_Peace"])
    expect(@subject.part).to eq(["this is a part"])
  end
  it "should set, persist, and recall values" do
    @subject.title = 'War and Peace'
    @subject.based_near = "Moscow, Russia"
    @subject.related_url = "http://en.wikipedia.org/wiki/War_and_Peace"
    @subject.part = "this is a part"
    @subject.save

    loaded = RdfTest.find(@subject.pid)
    expect(loaded.title).to eq('War and Peace')
    expect(loaded.based_near).to eq(['Moscow, Russia'])
    expect(loaded.related_url).to eq(['http://en.wikipedia.org/wiki/War_and_Peace'])
    expect(loaded.part).to eq(['this is a part'])
  end
  it "should set multiple values" do
    @subject.part = ["part 1", "part 2"]
    @subject.save

    loaded = RdfTest.find(@subject.pid)
    expect(loaded.part).to eq(['part 1', 'part 2'])
  end
  it "should append values" do
    @subject.part = "thing 1"
    @subject.save

    @subject.part << "thing 2"
    expect(@subject.part).to eq(["thing 1", "thing 2"])
  end
  it "should delete a value" do
    @subject.title = "Hamlet"
    @subject.save
    @subject.title = ""
    @subject.save
    expect(@subject.title).to be_nil
  end

  it "should be able to save a blank document" do
    @subject.title = ""
    @subject.save
  end

  it "should load n-triples into the graph" do
    ntrip = '<http://oregondigital.org/ns/62> <http://purl.org/dc/terms/type> "Image" .
<http://oregondigital.org/ns/62> <http://purl.org/dc/terms/spatial> "Benton County (Ore.)" .
'
    @subject.rdf.content = ntrip
    expect(@subject.rdf.graph.dump(:ntriples)).to eq(ntrip)
  end

  describe "using rdf_subject" do
    before do
      # reopening existing class
      class MyDatastream < ActiveFedora::NtriplesRDFDatastream
        rdf_subject { |ds| RDF::URI.new("http://oregondigital.org/ns/#{ds.pid.split(':')[1]}") }
        map_predicates do |map|
          map.type(:in => RDF::DC)
          map.spatial(:in => RDF::DC)
        end
      end
    end
    after do
      @subject.destroy
    end

    it "should write rdf with proper subjects" do
      @subject.rdf.type = "Frog"
      @subject.inner_object.pid = 'foo:99'
      @subject.save!
      @subject.reload
      expect(@subject.rdf.graph.dump(:ntriples)).to eq("<http://oregondigital.org/ns/99> <http://purl.org/dc/terms/type> \"Frog\" .\n")
      @subject.rdf.type == ['Frog']

    end

  end


  it "should delete values" do
    @subject.title = "Hamlet"
    @subject.related_url = "http://psu.edu/"
    @subject.related_url << "http://projecthydra.org/"
    @subject.save
    expect(@subject.title).to eq("Hamlet")
    expect(@subject.related_url).to include("http://psu.edu/")
    expect(@subject.related_url).to include("http://projecthydra.org/")
    @subject.title = ""
    @subject.related_url.delete("http://projecthydra.org/")
    @subject.save
    expect(@subject.title).to be_nil
    expect(@subject.related_url).to eq(["http://psu.edu/"])
  end
  it "should delete multiple values at once" do
    @subject.part = "MacBeth"
    @subject.part << "Hamlet"
    @subject.part << "Romeo & Juliet"
    expect(@subject.part.first).to eq("MacBeth")
    @subject.part.delete("MacBeth", "Romeo & Juliet")
    expect(@subject.part).to eq(["Hamlet"])
    expect(@subject.part.first).to eq("Hamlet")
  end
  it "should ignore values to be deleted that do not exist" do
    @subject.part = ["title1", "title2", "title3"]
    @subject.part.delete("title2", "title4", "title6")
    expect(@subject.part).to eq(["title1", "title3"])
  end
  describe "term proxy methods" do
    before(:each) do
      class TitleDatastream < ActiveFedora::NtriplesRDFDatastream
        map_predicates { |map| map.title(:in => RDF::DC) }
      end
      class Foobar < ActiveFedora::Base
        has_metadata :name=>'rdf', :type=>TitleDatastream
        delegate :title, :to=>'rdf'
      end
      @subject = Foobar.new
      @subject.title = ["title1", "title2", "title3"]
    end

    after(:each) do
      Object.send(:remove_const, :Foobar)
      Object.send(:remove_const, :TitleDatastream)
    end

    it "should support the count method to determine # of values" do
      expect(@subject.title.count).to eq(3)
    end
    it "should iterate over multiple values" do
      expect(@subject.title).to respond_to(:each)
    end
    it "should get the first value" do
      expect(@subject.title.first).to eq("title1")
    end
    it "should evaluate equality predictably" do
      expect(@subject.title).to eq(["title1", "title2", "title3"])
    end
    it "should support the empty? method" do
      expect(@subject.title).to respond_to(:empty?)
      expect(@subject.title.empty?).to be_falsey
      @subject.title.delete("title1", "title2", "title3")
      expect(@subject.title.empty?).to be_truthy
    end
    it "should support the is_a? method" do
      expect(@subject.title.is_a?(Array)).to eq(true)
    end
  end
end
