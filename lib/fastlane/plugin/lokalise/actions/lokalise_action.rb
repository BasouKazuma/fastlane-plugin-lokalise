require 'net/http'
require 'rubygems'

module Fastlane
  module Actions
    class LokaliseAction < Action

      def self.run(params)

        token = params[:api_token]
        project_identifier = params[:project_identifier]
        destination = params[:destination]
        clean_destination = params[:clean_destination]
        include_comments = params[:include_comments] ? 1 : 0
        use_original = params[:use_original] ? 1 : 0
        export_empty_as = params[:export_empty_as]
        export_sort = params[:export_sort]
        file_strategy = params[:file_strategy]

        request_data = {
          api_token: token,
          id: project_identifier,
          type: "strings",
          use_original: use_original,
          bundle_filename: "Localization.zip",
          bundle_structure: "%LANG_ISO%.lproj/Localizable.%FORMAT%",
          ota_plugin_bundle: 0,
          export_empty: "base",
          include_comments: include_comments,
          export_empty_as: export_empty_as,
          export_sort: export_sort
        }

        languages = params[:languages]
        if languages.kind_of? Array then
          request_data["langs"] = languages.to_json
        end

        tags = params[:tags]
        if tags.kind_of? Array then
          request_data["include_tags"] = tags.to_json
        end

        uri = URI("https://api.lokalise.co/api/project/export")
        request = Net::HTTP::Post.new(uri)
        request.set_form_data(request_data)

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        response = http.request(request)

        jsonResponse = JSON.parse(response.body)
        UI.error "Bad response 🉐\n#{response.body}" unless jsonResponse.kind_of? Hash
        if jsonResponse["response"]["status"] == "success" && jsonResponse["bundle"]["file"].kind_of?(String)  then
          UI.message "Downloading localizations archive 📦"
          FileUtils.mkdir_p("lokalisetmp")
          fileURL = jsonResponse["bundle"]["full_file"]
          uri = URI(fileURL)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true
          zipRequest = Net::HTTP::Get.new(uri)
          response = http.request(zipRequest)
          if response.content_type == "application/zip" or response.content_type == "application/octet-stream" then
            FileUtils.mkdir_p("lokalisetmp")
            open("lokalisetmp/a.zip", "wb") { |file| 
              file.write(response.body)
            }
            unzip_file("lokalisetmp/a.zip", destination, clean_destination, file_strategy)
            FileUtils.remove_dir("lokalisetmp")
            UI.success "Localizations extracted to #{destination} 📗 📕 📘"
          else
            UI.error "Response did not include ZIP"
          end
        elsif jsonResponse["response"]["status"] == "error"
          code = jsonResponse["response"]["code"]
          message = jsonResponse["response"]["message"]
          UI.error "Response error code #{code} (#{message}) 📟"
        else
          UI.error "Bad response 🉐\n#{jsonResponse}"
        end
      end


      def self.unzip_file(file, destination, clean_destination, file_strategy)
        Zip::File.open(file) { |zip_file|
          if clean_destination then
            UI.message "Cleaning destination folder ♻️"
            FileUtils.remove_dir(destination)
            FileUtils.mkdir_p(destination)
          end
          UI.message "Unarchiving localizations to destination 📚"
           zip_file.each { |f|
             f_path= File.join(destination, f.name)
             FileUtils.mkdir_p(File.dirname(f_path))
             if file_strategy == "override" then
               override_file(zip_file, f, f_path)
             else if file_strategy == "merge"
               merge_file(zip_file, f, f_path)
             else 
               update_file(zip_file, f, f_path)
             end
           }
        }
      end
        
      def self.override_file(zip_file, file, path)
        FileUtils.rm(path) if File.file? path
        zip_file.extract(file, path)
      end
          
      def self.merge_file(zip_file, file, path)
        if File.file? path then
          tempFilePath = "lokalisetmp/" + file.name
          
          FileUtils.rm(tempFilePath) if File.file? tempFilePath
          FileUtils.mkdir_p(File.dirname(tempFilePath))
          zip_file.extract(file, tempFilePath)
          
          translations = Hash.new
          
          destFile = File.open(path, "r")
          destFile.each_line do |oldLine|
            oldKeyValue = oldLine.split('" = "')
            translations[oldKeyValue[0]] = oldKeyValue[1]
          end
          destFile.close
          
          tempFile = File.open(tempFilePath, "r")
          tempFile.each_line do |newLine|
            newKeyValue = newLine.split('" = "')
            translations[newKeyValue[0]] = newKeyValue[1]
          end
          tempFile.close
          
          write_file(translations, path)
          else
          zip_file.extract(file, path)
        end
      end
      
      def self.update_file(zip_file, file, path)
        if File.file? path then
          tempFilePath = "lokalisetmp/" + file.name
          
          FileUtils.rm(tempFilePath) if File.file? tempFilePath
          FileUtils.mkdir_p(File.dirname(tempFilePath))
          zip_file.extract(file, tempFilePath)
          
          translations = Hash.new
          
          destFile = File.open(path, "r")
          destFile.each_line do |oldLine|
            oldKeyValue = oldLine.split('" = "')
            translations[oldKeyValue[0]] = oldKeyValue[1]
          end
          destFile.close
          
          tempFile = File.open(tempFilePath, "r")
          tempFile.each_line do |newLine|
            newKeyValue = newLine.split('" = "')
            translations[newKeyValue[0]] = newKeyValue[1] unless translations[newKeyValue[0]].nil?
          end
          tempFile.close
          
          write_file(translations, path)
          else
          zip_file.extract(file, path)
        end
      end
        
      def self.write_file(translations, path)
        FileUtils.rm(path) if File.file? path
        
        sortedTranslations = Hash[ translations.sort_by { |key, val| key.downcase } ]
        
        File.open(path, "w+") do |file|
          sortedTranslations.each { |key, value|
            leftSide = key
            rightSide = value
            line = "#{leftSide}\" = \"#{rightSide}"
            file.write(line)
          }
        end
      end

      #####################################################
      # @!group Documentation
      #####################################################


      def self.description
        "Download Lokalise localization"
      end


      def self.available_options
        [
          FastlaneCore::ConfigItem.new(key: :api_token,
                                       env_name: "LOKALISE_API_TOKEN",
                                       description: "API Token for Lokalise",
                                       verify_block: proc do |value|
                                          UI.user_error! "No API token for Lokalise given, pass using `api_token: 'token'`" unless (value and not value.empty?)
                                       end),
          FastlaneCore::ConfigItem.new(key: :project_identifier,
                                       env_name: "LOKALISE_PROJECT_ID",
                                       description: "Lokalise Project ID",
                                       verify_block: proc do |value|
                                          UI.user_error! "No Project Identifier for Lokalise given, pass using `project_identifier: 'identifier'`" unless (value and not value.empty?)
                                       end),
          FastlaneCore::ConfigItem.new(key: :destination,
                                       description: "Localization destination",
                                       verify_block: proc do |value|
                                          UI.user_error! "Things are pretty bad" unless (value and not value.empty?)
                                          UI.user_error! "Directory you passed is in your imagination" unless File.directory?(value)
                                       end),
          FastlaneCore::ConfigItem.new(key: :clean_destination,
                                       description: "Clean destination folder",
                                       optional: true,
                                       is_string: false,
                                       default_value: false,
                                       verify_block: proc do |value|
                                          UI.user_error! "Clean destination should be true or false" unless [true, false].include? value
                                       end),
          FastlaneCore::ConfigItem.new(key: :languages,
                                       description: "Languages to download",
                                       optional: true,
                                       is_string: false,
                                       verify_block: proc do |value|
                                          UI.user_error! "Language codes should be passed as array" unless value.kind_of? Array
                                       end),
            FastlaneCore::ConfigItem.new(key: :include_comments,
                                       description: "Include comments in exported files",
                                       optional: true,
                                       is_string: false,
                                       default_value: false,
                                       verify_block: proc do |value|
                                         UI.user_error! "Include comments should be true or false" unless [true, false].include? value
                                       end),
            FastlaneCore::ConfigItem.new(key: :use_original,
                                       description: "Use original filenames/formats (bundle_structure parameter is ignored then)",
                                       optional: true,
                                       is_string: false,
                                       default_value: false,
                                       verify_block: proc do |value|
                                         UI.user_error! "Use original should be true of false." unless [true, false].include?(value)
                                        end),
            FastlaneCore::ConfigItem.new(key: :tags,
                                        description: "Include only the keys tagged with a given set of tags",
                                        optional: true,
                                        is_string: false,
                                        type: Array,
                                        verify_block: proc do |value|
                                          UI.user_error! "Tags should be passed as array" unless value.kind_of? Array
                                        end),
            FastlaneCore::ConfigItem.new(key: :export_empty_as,
                                       description: "Define the strategy for empty translations. Possible values are: [empty, base, skip]",
                                       optional: true,
                                       is_string: true,
                                       default_value: "empty",
                                       verify_block: proc do |value|
                                         UI.user_error! "export_empty_as should be defined as empty, base or skip." unless ["empty", "base", "skip"].include?(value)
                                        end),
            FastlaneCore::ConfigItem.new(key: :file_strategy,
                                       description: "Use original filenames/formats (bundle_structure parameter is ignored then)",
                                       optional: true,
                                       is_string: true,
                                       default_value: "override",
                                       verify_block: proc do |value|
                                         UI.user_error! "File strategy should be override, merge or update." unless ["override", "merge", "update"].include?(value)
                                        end),
            FastlaneCore::ConfigItem.new(key: :export_sort,
                                       description: "Define the strategy for sorting translations. Possible values are: [first_added, last_added, last_updated, a_z, z_a]",
                                       optional: true,
                                       is_string: true,
                                       default_value: "last_added",
                                       verify_block: proc do |value|
                                         UI.user_error! "export_sort should be defined as first_added, last_added, last_updated, a_z or z_a." unless ["first_added", "last_added", "last_updated", "a_z", "z_a"].include?(value)
                                        end),
        ]
      end


      def self.authors
        "Fedya-L"
      end


      def self.is_supported?(platform)
        [:ios, :android, :mac].include? platform 
      end


    end
  end
end
