require 'rubygems'
require "right_api_client"
  
def initialize_api_client(options = {})
  # Require gems in initialize
  account_id=
    email='curt@rightscale.com'
  password=''
  api_url = 'https://my.rightscale.com'
  options = {
    account_id: account_id,
    email: email,
    password: password,
    api_url: api_url
  }.merge options

  RightApi::Client.new(options)
end