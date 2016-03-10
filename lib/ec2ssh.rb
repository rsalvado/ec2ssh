require 'etc'
require 'active_support/core_ext/object/blank'
require 'active_support/core_ext/kernel/reporting'
require 'highline/import'
silence_warnings { require 'aws' }
require 'yaml'
require 'fileutils'
require 'terminal-table'

module Ec2ssh

  class UnavailableEC2Credentials < StandardError; end

  class App

    def initialize(file = "~/.ec2ssh", account=:default)
      @config = read_aws_config(file, account)
    end

    def select_instance(instances=[], filter_tag = nil, filter_ip = nil, filter_sg = nil)
      # TODO: Order by region
      # TODO: Ansi colors https://github.com/JEG2/highline/blob/master/examples/ansi_colors.rb
      account_name = @config[:account_name]
      instances = get_all_ec2_instances
      n = 0
      hostnames = []
      rows = []
      instances.each do |i|
        if i[:aws_state] == "running" && check_filter_tag( filter_tag, i ) && check_filter_ip( filter_ip, i ) && check_filter_sg( filter_sg, i )
          rows << [n, i[:aws_instance_id], i[:tags]["Name"], [:aws_groups].join(','), i[:dns_name], i[:aws_private_ip_address]]
          hostnames << i[:dns_name]
          n = n + 1
	end
      end
      if n == 0
        puts "No hosts found in #{account_name} account"
      else
        table = Terminal::Table.new :title => account_name, :headings => ['#', 'instance_id', 'name', 'SG', 'dns_name', 'private_ip'], :rows => rows
        puts table
        template = @config[:template] || "ssh #{Etc.getlogin}@<instance>"
        selected_host = ask("Host?  ", Integer) { |q| q.in = 0..hostnames.count }
        command = template.gsub("<instance>",hostnames[selected_host])
        exec(command)
      end
    end

    private

    def read_aws_config(file, account=:default)
      file = File.expand_path(file)
      accounts = YAML::load(File.open(file))
      selected_account = accounts[account] || accounts.first[1]
    rescue Errno::ENOENT
      puts "ec2ssh config file doesn't exist. Creating a new ~/.ec2ssh. Please review it customize it."
      sample_config_file = File.join(File.dirname(__FILE__), "templates/ec2ssh_config_sample.yaml")
      FileUtils.cp sample_config_file, File.expand_path("~/.ec2ssh")
      exit
    end

    def get_all_ec2_regions
      %w(eu-west-1 us-east-1 ap-northeast-1 us-west-1 ap-southeast-1)
    end

    def get_all_ec2_instances
      id = @config[:id]
      key = @config[:key]
      regions ||= @config[:regions] || get_all_ec2_regions
      instances = regions.map do |region|
        silence_stream STDOUT do
          Aws::Ec2.new(id, key, :region => region).describe_instances
        end
      end.flatten
    rescue Aws::AwsError => e
      abort "AWS Error. #{e.message}"
    end

    def check_filter_tag( filter, instance )
      return true unless filter
      instance[:tags]["Name"].to_s.include? filter
    end

    def check_filter_ip( filter, instance )
      return true unless filter
      instance[:aws_private_ip_address].to_s.include? filter
    end

    def check_filter_sg( filter, instance )
      return true unless filter
      instance[:aws_groups].to_s.include? filter
    end

  end

end
