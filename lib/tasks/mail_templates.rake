# frozen_string_literal: true

namespace :mail_templates do
  desc "Load the mail templates that ship with the Clubhouse into the database"
  task load: :environment do
    labels = {
      created: "Added",
      updated: "Brought up to date",
      unchanged: "Already current",
      edited: "Left alone, edited in the Clubhouse"
    }

    results = MailTemplateSeeds.load!

    if results.values.all?(&:empty?)
      puts "No mail templates found in #{MailTemplateSeeds::DIRECTORY}."
    else
      results.each do |outcome, tags|
        next if tags.empty?

        puts "#{labels.fetch(outcome)} (#{tags.size}):"
        tags.each { |tag| puts "  #{tag}" }
      end
    end
  end
end
