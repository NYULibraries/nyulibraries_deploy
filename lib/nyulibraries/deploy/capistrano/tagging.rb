require 'capistrano'
require 'git'
require 'mail'
require 'thor'
require 'net/http'

# Capistrano::Configuration.instance(:must_exist).load do  # 
  # before 'deploy:cleanup',  'tagging:deploy'

  namespace :tagging do
    desc "Make sure branch is checked out and up to date before tagging"
    task :checkout_branch do
      puts "TASK:\ttagging:checkout_branch  =>  Checking out git repo for tagging."
      if tagging_environment?
        sh "git fetch --all; true"
        sh "git checkout #{fetch :previous_revision}; true"
        sh "git reset --hard origin/HEAD; true"
      else
        puts "Ignoring checking out branch in this environment."
      end
    end
    
    desc "Create release tag in local and origin repo"
    task :deploy do
      puts "TASK:\ttagging:deploy  =>  Creating tags on Git repo."
      if tagging_environment?
        create_tag
      else
        puts "Ignoring tagging in this environment."
      end
    end
    
    desc "Sends git diff"
    task :send_diff do
      puts "TASK:\ttagging:send_diff  =>  Sending diff on Git tags."
      if tagging_environment?
        mail_setup
        mail = Mail.new
        mail[:from]     = 'no-reply@library.nyu.edu'
        mail[:body]     = git_compare
        mail[:subject]  = "Recent changes for #{fetch(:app_title, 'this project')}"
        mail[:to]       = fetch(:recipient, "")
        begin
          mail.deliver! unless mail[:to].to_s.empty?
          puts mail[:to].to_s.empty? ? "Diff not sent, recipient not found. Be sure to `set :recipient, 'you@host.tld'`" : "Diff sent to #{mail[:to]}"
        rescue
          puts "Could not send mail."
          puts "#{mail}"
        end
      else
        puts "Ignored send diff in #{fetch(:rails_env, fetch(:stage, 'staging'))} environment"
      end
    end
    
    def current_tag
      @current_tag ||= fetch(:current_tag, "")
    end
    
    def previous_tag
      @previous_tag ||= fetch(:previous_tag, "")
    end

    def remote
      @remote = fetch(:tagging_remote, "")
    end

    def user_name
      @user_name ||= `git config --get user.name`.chomp
    end

    def user_email
      @user_email ||= `git config --get user.email`.chomp
    end
    
    def repo_name
      @repo_name ||= "#{fetch(:repository).scan(/:(.*)\.git/).last.first}"
    end
    
    def git_tag_names
      @git_tag_names ||= git.tags.collect {|tag| tag.name}
    end
    
    def tagging_environment?
      return true if fetch(:tagging_environments).nil?
      fetch(:tagging_environments).collect {|environment| environment.to_sym}.include?(fetch(:stage, fetch(:rails_env, :staging)).to_sym)
    end
    
    def current_tag?
      current_tag.empty? || git_tag_names.include?(current_tag)
    end
    
    def previous_tag?
      previous_tag.empty? || git_tag_names.include?(previous_tag)
    end
    
    def git
      git = Git.open(Dir.pwd.to_s)
      git.fetch
      git
    end
    
    def git_io url
      Net::HTTP.post_form(URI.parse("http://git.io/"), {:url => url})['location']
    end
    
    def git_compare
      if current_tag?
        git_link = "https://www.github.com/#{repo_name}/compare/" +(previous_tag? ? "#{previous_tag}" : "#{fetch(:previous_revision, git.log.collect.first(2).last.sha)}") + "...#{current_tag}"
        return "Something has changed in #{fetch(:app_title, 'this project')}!\n Check out this sick compare: #{git_io git_link}"
      end
      return "There was a redeployment in #{fetch(:app_title, 'this project')}, however there is nothing to compare."
    end
    
    def mail_setup
      Mail.defaults do
        delivery_method :smtp, { 
          :openssl_verify_mode => OpenSSL::SSL::VERIFY_NONE, 
          :address => 'mail.library.nyu.edu',
          :port => '25',
          :enable_starttls_auto => true
        }
      end
    end

    def create_tag
      if tagging_environment?
        sh "git tag #{current_tag} #{fetch :previous_revision} -m \"Deployed by #{user_name} <#{user_email}>\"; true"
        sh "git push #{remote} refs/tags/#{current_tag}:refs/tags/#{current_tag}; true"
      else
        puts "ignored git tagging in #{fetch(:rails_env, fetch(:stage, 'staging'))} environment"
      end
    end

    
  end
  # 
  # before 'tagging:deploy',  'tagging:checkout_branch'
  # after  'tagging:deploy',  'tagging:send_diff'
  
  before  'tagging:deploy',   'tagging:checkout_branch'
  after   'tagging:deploy',   'tagging:send_diff'
  after   'deploy:finished',  'tagging:deploy'
# end
