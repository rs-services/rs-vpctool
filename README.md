rs-vpctool
==========

This tool is used to create a VPC reference in the RightScale dashboard (http://us-3.rightscale.com)  When running the command you get a new
VPC network, internet gateway, public and private subnets, route tables, routes and a VPC NAT Host in one public subnet.


### Clouds Supported
* AWS

### Installation
* Install Ruby 1.9.3 or later
* gem install bundler
* git clone git@github.com:rs-services/rs-vpctool.git
* cd rs-vpctool
* bundle install


### Configuration
1. Import the VPC NAT Host ServerTemplate (https://us-3.rightscale.com/library/server_templates/AWS-VPC-NAT-ServerTemplate-13-/lineage/47816) into your RightScale account.
2. Create a new RightScale deployment for your testing.    
3. update the config/network.yml with your parameters
4. update the config/login.yml with your login credentials

### Running
WARNING: Using an existing deployment or VPC name in your network.yml file,  they may be deleted or changed. 
Choose new VPC name and Deployment for your testing reference.

In your console run rs-vpctool/bin/vpctool


**Report problems or requests in the github repository issues section**


 




