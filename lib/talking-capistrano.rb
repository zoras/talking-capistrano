require "talking-capistrano/version"
require 'json'

module TalkingCapistrano
  module SkypeNotification

    require 'skype_script_invoker'   

    class << self; 
      attr_accessor :topic;
      attr_accessor :skyper;

    end

    def self.set_notify(topic_exist)
      @notify = topic_exist
      @topic = topic_exist if topic_exist
      @skyper = SkypeScriptInvoker.new(@topic)
    end

    def self.notify?
      @notify
    end

    def self.notify(text)
        @skyper.send_message(pad_text text) unless @topic.nil?
    end

    def self.pad_text(text)
      "\\\\ #{text} //"
    end
  end
end

module TalkingCapistrano
  
  @DATA_SET = JSON.load( File.read(File.join(File.dirname(__FILE__), '/talking-capistrano.json' )) )

  class << self; 
      attr_accessor :local_rails_env; 
  end

  def self.say_deploy_started(branch = nil)
      branch_txt = defined?(branch) ? ", branch: " + branch  : ""
     get_item(:say_deploy_started).sub!  "ENV", "#{@local_rails_env}#{branch_txt}"
  end
  def self.say_deploy_completed
     get_item(:say_deploy_completed).sub!  "ENV", @local_rails_env
  end
  def self.say_deploy_failed
     get_item(:say_deploy_failed).sub!  "ENV", @local_rails_env
  end
  def self.say_speaker_name
     get_item(:voices)
  end  

  private

  def self.get_item(arr)
      @DATA_SET[arr.to_s].sample
  end 
end

## In a capistrano scope
Capistrano::Configuration.instance.load do

      set :say_command, "say"

      #Say related tasks to notify deployments to the group
      namespace :deploy do
        namespace :say do
          task :about_to_deploy do
            system("#{say_command} #{TalkingCapistrano::say_deploy_started fetch(:branch, nil)} -v '#{TalkingCapistrano::say_speaker_name}' &")
          end
          task :setup do
              TalkingCapistrano.local_rails_env = fetch(:stage, "-unknown env-").to_s
          end                  
        end
      end

      #Overide capistrano code deploy, to add the on error hook, seems to not be called otherwise
      namespace :deploy do
        task :update_code, :except => { :no_release => true } do
          on_rollback do
            fail_str = TalkingCapistrano::say_deploy_failed
            system("#{say_command} #{fail_str} -v #{TalkingCapistrano::say_speaker_name} &");
                TalkingCapistrano::SkypeNotification.notify(fail_str)
              run "rm -rf #{release_path}; true" 
          end
          strategy.deploy!
          finalize_update
        end
      end

      namespace :deploy do
        namespace :skype_notifications do
          task :setup do 
              TalkingCapistrano::SkypeNotification.set_notify(fetch(:skype_topic, false))
        end
        task :send_about_to_deploy do
            TalkingCapistrano::SkypeNotification.notify(TalkingCapistrano::say_deploy_started fetch(:branch, nil))
        end      
      end
    end

      #setup tasks for say and skype
      before "deploy", "deploy:skype_notifications:setup"
      before "deploy", "deploy:say:setup"

      # Skype notifications on deploy stages
      before "deploy", "deploy:skype_notifications:send_about_to_deploy"      

      # Say notifications on deploy stages
      before "deploy", "deploy:say:about_to_deploy"
      # Say + Skype notifications on deploy stages - hack to avoid stack too deep exception
      after   "deploy" do
        completed_str = TalkingCapistrano::say_deploy_completed
        `#{say_command} #{completed_str} -v '#{TalkingCapistrano::say_speaker_name}' &`
           TalkingCapistrano::SkypeNotification.notify(completed_str)
      end

end