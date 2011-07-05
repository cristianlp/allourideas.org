class SessionInfo< ActiveRecord::Base
	serialize :loc_info
	serialize :loc_info_2
	has_many :trials
	has_many :clicks
	has_many :alternatives, :class_name => "Abingo::Alternative", :through => :trials #Tracking A/B tests
	belongs_to :visitor
	belongs_to :user

	after_create :do_geolocate

	def do_geolocate
		logger.info("Doing geolocation after create")
		self.send_later :geolocate!, self.ip_addr
		#delete ip_addr here
	end

	def geolocate!(ip_address)
	      # We want to geolocate using both sources in case one has better information
	      self.loc_info = GEOIP_DB.look_up(ip_address)
	      self.loc_info = {} if self.loc_info.blank? || loc_info[:latitude].nil? || loc_info[:longitude].nil?


	      if(ip_address == "127.0.0.1")
		      logger.info("Private ip - not geolocating ")
	      else
		      loc = Geokit::Geocoders::MultiGeocoder.geocode(ip_address)
		      if loc.success
			      self.loc_info_2= {}
			      self.loc_info_2[:city] = loc.city
			      self.loc_info_2[:region] = loc.state
			      self.loc_info_2[:country_code] = loc.country
			      self.loc_info_2[:latitude] = loc.lat
			      self.loc_info_2[:longitude] = loc.lng
		      end
	      end

	      self.loc_info_2 = {} if self.loc_info_2.blank? || loc_info_2[:latitude].nil? || loc_info_2[:longitude].nil?

              self.ip_addr = Digest::MD5.hexdigest([ip_address, IP_ADDR_HASH_SALT].join(""))
	      self.save
	end

  # gets all clicks that are entrances to the earl that is
  # identified by the array of slugs
  def marketplace_entrances(slugs)
    return @marketplace_entrances if @marketplace_entrances
    slugw = slugs.map {|s| "url like ?"}.join(" OR ")
    slugv = slugs.map {|s| "%/#{s.name}%"}
    conditions  = ["controller = 'earls' AND action = 'show' AND (#{slugw})"]
    conditions += slugv
    @marketplace_entrances = self.clicks.find(:all, :select => "id, referrer, created_at", :conditions => conditions, :order => 'created_at DESC')
  end

  # find the entrance referrer that is newest, but older than date
  def entrance_referrer(slugs, date)
    entrances = marketplace_entrances(slugs)
    # entrances are sorted by created_at DESC
    # this could be optimized with binary a search
    entrances.each do |entrance|
      return entrance.referrer if entrance.created_at < date
    end
    nil
  end

  def vote_clicks
    return @vote_clicks if @vote_clicks
    conditions = ["controller = 'prompts' AND (action = 'vote' OR action='skip')"]
    @vote_clicks = clicks.find(:all, :select => "id, created_at, referrer", :conditions => conditions, :order => 'created_at DESC')
  end

  def find_click_for_vote(vote)
    vc = vote_clicks
    click = bSearch(vc, vote['Created at'], 0, vc.length)
    return (click) ? click : Click.new
  end

  def clicks_with_tracking
    return @clicks_with_tracking if @clicks_with_tracking
    conditions = ["referrer LIKE ?", '%tracking=%']
    @clicks_with_tracking = clicks.find(:all, :select => "id, created_at, referrer", :conditions => conditions, :order => 'created_at DESC')
  end

  def find_tracking_value(vote)
    ref_ts = clicks_with_tracking.select do |click|
      click.created_at <= vote['Created at']
    end
    tracking = ref_ts.map do |ref|
      begin
        CGI.parse(URI.parse(ref.referrer).query)['tracking']
      rescue
        nil
      end
    end.flatten.compact.first
  end

  private
    def bSearch(arr, val, low, high)
      return nil if low > high
      mid = low + ((high - low) / 2).to_i
      return nil if mid > arr.length - 1

      if arr[mid].created_at > val
        return bSearch(arr, val, mid+1, high)
      elsif arr[mid].created_at <= val
        # we've found the value if it is less than or equal
        # and we're at beginning of array or value before this one is greater
        if (mid == 0 || arr[mid-1].created_at > val)
          return arr[mid]
        else
          return bSearch(arr, val, low, mid-1)
        end
      end
    end
end

