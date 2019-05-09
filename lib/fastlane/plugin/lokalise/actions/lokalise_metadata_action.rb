require 'net/http'


module Fastlane
  module Actions
    class LokaliseMetadataAction < Action

      @params
      def self.run(params)
        @params = params

        case @params[:platform]
        when "ios"
            case @params[:action]
            when "download_from_lokalise"
                metadata = get_metadata_from_lokalise()
                write_lokalise_translations_to_itunes_metadata(metadata)
            when "upload_to_lokalise"
                metadata = get_metadata()
                add_languages = params[:add_languages]
                override_translation = params[:override_translation]
                if add_languages == true
                  create_languages(metadata.keys)
                end
                if override_translation == true
                  upload_metadata_itunes(metadata) unless metadata.empty?
                else
                  lokalise_metadata = get_metadata_from_lokalise()
                  filtered_metadata = filter_metadata(metadata, lokalise_metadata)
                  upload_metadata_itunes(filtered_metadata) unless filtered_metadata.empty?
                end
            end
        when "android"
            case @params[:action]
            when "download_from_lokalise"
                release_number = params[:release_number]
                UI.user_error! "Release number is required for Android (should be an integer and greater that 0)" unless (release_number and release_number.is_a?(Integer) and release_number > 0)
                metadata = get_metadata_from_lokalise()
                write_lokalise_translations_to_googleplay_metadata(metadata, release_number)
            when "upload_to_lokalise"
                metadata = get_metadata()
                add_languages = params[:add_languages]
                override_translation = params[:override_translation]
                if add_languages == true 
                  create_languages(metadata.keys)
                end
                if override_translation == true
                  upload_metadata_google_play(metadata) unless metadata.empty?
                else
                  lokalise_metadata = get_metadata_from_lokalise()
                  filtered_metadata = filter_metadata(metadata, lokalise_metadata)
                  upload_metadata_google_play(filtered_metadata) unless filtered_metadata.empty?
                end
            end
        end

      end


      def self.create_languages(languages)
        data = {
          iso: languages.map { |language| fix_language_name(language, true) } .to_json
        }
        make_request("language/add", data)
      end


      def self.filter_metadata(metadata, other_metadata)
        filtered_metadata = {}
        metadata.each { |language, translations|
          other_translations = other_metadata[language]
          filtered_translations = {}
          
          if other_translations != nil && other_translations.empty? == false
            translations.each { |key, value|
              other_value = other_translations[key]
              filtered_translations[key] = value unless other_value != nil && other_value.empty? == false
            }
          else 
            filtered_translations = translations
          end

          filtered_metadata[language] = filtered_translations unless filtered_translations.empty?
        }
        return filtered_metadata
      end


      def self.write_lokalise_translations_to_itunes_metadata(metadata)
        metadata_key_file_itunes().each { |key, parameter|
          final_translations = {}
          metadata.each { |lang, translations|
            if translations.empty? == false
              translation = translations[key]
              final_translations[lang] = translation if translation != nil && translation.empty? == false
              metadata_path = get_metadata_path()
              path = File.join(metadata_path, lang)
              filename = "#{parameter}.txt"
              output_file = File.join(path, filename)
              FileUtils.mkdir_p(path) unless File.exist?(path)
              puts "Updating '#{output_file}'..."
              File.open(output_file, 'wb') do |file|
                file.write(final_translations[lang])
              end
            end 
          }
        }
      end


      def self.write_lokalise_translations_to_googleplay_metadata(metadata, release_number)
        metadata_key_file_googleplay().each { |key, parameter|
          final_translations = {}
          metadata.each { |lang, translations|
            if translations.empty? == false
              translation = translations[key]
              final_translations[lang] = translation if translation != nil && translation.empty? == false
              metadata_path = get_metadata_path()
              if "#{parameter}" ==  "changelogs"
                path = File.join(metadata_path, lang, parameter)
                filename = "#{release_number}.txt"
              else
                path = File.join(metadata_path, lang)
                filename = "#{parameter}.txt"
              end
              output_file = File.join(path, filename)
              FileUtils.mkdir_p(path) unless File.exist?(path)
              puts "Updating '#{output_file}'..."
              File.open(output_file, 'wb') do |file|
                file.write(final_translations[lang])
              end
            end
          }
        }
      end


      def self.make_request(path, data)

        request_data = {
          api_token: @params[:api_token],
          id: @params[:project_identifier]
        }.merge(data)

        uri = URI("https://api.lokalise.co/api/#{path}")
        request = Net::HTTP::Post.new(uri)
        request.set_form_data(request_data)
  
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        response = http.request(request)

        jsonResponse = JSON.parse(response.body)
        raise "Bad response 🉐\n#{response.body}" unless jsonResponse.kind_of? Hash
        if jsonResponse["response"]["status"] == "success"  then
          UI.success "Response #{jsonResponse} 🚀"
        elsif jsonResponse["response"]["status"] == "error"
          code = jsonResponse["response"]["code"]
          message = jsonResponse["response"]["message"]
          raise "Response error code #{code} (#{message}) 📟"
        else
          raise "Bad response 🉐\n#{jsonResponse}"
        end
        return jsonResponse
      end


      def self.upload_metadata(metadata_keys, metadata)
        keys = []
        metadata_keys.each do |key, value|
          key = make_key_object_from_metadata(key, metadata)
          if key 
            keys << key
          end
        end
        data = {
          data: keys.to_json
        }
        make_request("string/set", data)
      end


      def self.upload_metadata_itunes(metadata)
        upload_metadata(metadata_key_file_itunes, metadata)
      end


      def self.upload_metadata_google_play(metadata)
        upload_metadata(metadata_key_file_googleplay, metadata)
      end


      def self.make_key_object_from_metadata(key, metadata)
        key_data = {
          "key" => key,
          "platform_mask" => 16,
          "translations" => {}
        }
        metadata.each { |iso_code, data|
          translation = data[key]
          unless translation == nil || translation.empty?
            key_data["translations"][fix_language_name(iso_code, true)] = translation
          end
        }
        unless key_data["translations"].empty? 
          return key_data
        else
          return nil
        end
      end


      def self.get_metadata_path()
        if @params[:metadata_path]
          metadata_path = @params[:metadata_path]
        else
          case @params[:platform]
          when "android"
            metadata_path = "fastlane/metadata/android/"
          else
            metadata_path = "fastlane/metadata/"
          end
        end
        return metadata_path
      end


      def self.get_metadata()
        case @params[:platform]
        when "ios"
          available_languages = itunes_connect_languages
        when "android"
          available_languages = google_play_languages
        end
        metadata_path = get_metadata_path()
        complete_metadata = {}
        available_languages.each { |iso_code|
          language_directory = File.join(metadata_path, iso_code)
          if Dir.exist? language_directory
            language_metadata = {}
            case @params[:platform]
            when "ios"
              metadata_key_file_itunes().each { |key, file|
                populate_hash_key_from_file(language_metadata, key, File.join(language_directory, "#{file}.txt"))
              }
            when "android"
              metadata_key_file_googleplay().each { |key, file|
                if file == "changelogs"
                  changelog_directory = File.join(language_directory, "changelogs")
                  files = Dir.entries("#{changelog_directory}")
                  collectedFiles = files.collect { |s| s.partition(".").first.to_i }
                  sortedFiles = collectedFiles.sort
                  populate_hash_key_from_file(language_metadata, key, File.join(language_directory, "changelogs", "#{sortedFiles.last}.txt"))
                else
                  populate_hash_key_from_file(language_metadata, key, File.join(language_directory, "#{file}.txt"))
                end
              }
            end
            complete_metadata[iso_code] = language_metadata
          end
        }
        return complete_metadata
      end


      def self.get_metadata_from_lokalise()
        case @params[:platform]
        when "ios"
          valid_keys = metadata_key_file_itunes().keys
          valid_languages = itunes_connect_languages_in_lokalise()
          key_name = "key_ios"
        when "android"
          valid_keys = metadata_key_file_googleplay().keys
          valid_languages = google_play_languages_in_lokalise()
          key_name = "key_android"
        end
        data = {
          platform_mask: 16,
          keys: valid_keys.to_json,
        }
        response = make_request("string/list", data)
        metadata = {}
        response["strings"].each { |lang, translation_objects|
          if valid_languages.include?(lang)
            translations = {}
            translation_objects.each { |object|
              # The key can named differently depending on how the Lokalise Project was set up
              key = object[key_name]
              if !key
                key = object['key']
              end
              translation = object["translation"]
              if valid_keys.include?(key) && translation != nil && translation.empty? == false 
                translations[key] = translation
              end
            }
            if translations.empty? == false
              metadata[fix_language_name(lang)] = translations
            end
          end
        }
        return metadata
      end


      def self.populate_hash_key_from_file(hash, key, filepath)
        begin
          text = File.read filepath
          text.chomp!
          hash[key] = text unless text.empty?
        rescue => exception
          raise exception
        end
      end


      def self.metadata_key_file_itunes()
        return {
          "appstore.app.name" => "name",
          "appstore.app.description" => "description",
          "appstore.app.keywords" => "keywords",
          "appstore.app.promotional_text" => "promotional_text",
          "appstore.app.release_notes" => "release_notes",
          "appstore.app.subtitle" => "subtitle",
          "appstore.app.marketing_url" => "marketing_url",
          "appstore.app.privacy_url" => "privacy_url",
          "appstore.app.support_url" => "support_url",
        }
      end


      def self.metadata_key_file_googleplay()
        return {
          "googleplay.app.title" => "title",
          "googleplay.app.full_description" => "full_description",
          "googleplay.app.short_description" => "short_description",
          "googleplay.app.changelogs" => "changelogs",
        }
      end


      def self.itunes_connect_languages_in_lokalise()
        return itunes_connect_languages().map { |lang| 
          fix_language_name(lang, true) 
        }
      end


      def self.google_play_languages_in_lokalise()
        return google_play_languages().map { |lang| 
          fix_language_name(lang, true) 
        }
      end


      def self.itunes_connect_languages()
        languages = FastlaneCore::Languages::ALL_LANGUAGES
        languages.each do |lang|
            lang.gsub!("_", '-')
        end
        return languages
      end


      def self.google_play_languages()
        languages = Supply::Languages::ALL_LANGUAGES
        languages.each do |lang|
            lang.gsub!("_", '-')
        end
        return languages
      end


      def self.itunes_to_lokalise_language_map()
        return {
          "nl-NL" => "nl",
          "en-US" => "en",
          "hi" => "hi_IN",
          "zh-Hans" => "zh_CN",
          "zh-Hant" => "zh_TW"
        }
      end


      def self.googleplay_to_lokalise_language_map()
        return {
          "cs-CZ" => "cs",
          "da-DK" => "da",
          "fi-FI" => "fi",
          "iw-IL" => "he",
          "hu-HU" => "hu",
          "hy-AM" => "hy",
          "ja-JP" => "ja",
          "ko-KR" => "ko",
          "ky-KG" => "ky",
          "lo-LA" => "lo",
          "mr-IN" => "mr",
          "my-MM" => "my",
          "no-NO" => "no",
          "si-LK" => "si",
          "sl" => "sl_SI",
          "tr-TR" => "tr"
        }
      end


      def self.fix_language_name(language, for_lokalise = false)
        if @params[:platform] == "android"
          language_map = googleplay_to_lokalise_language_map()
        else
          language_map = itunes_to_lokalise_language_map()
        end
        if for_lokalise
          if language_map.key?(language)
            return language_map[language]
          else
            return language.gsub("-", "_")
          end
        else
          language_map = language_map.invert
          if language_map.key?(language)
            return language_map[language]
          else
            return language.gsub("_", "-")
          end
        end
      end


      #####################################################
      # @!group Documentation
      #####################################################


      def self.description
        "Upload metadata to lokalise."
      end


      def self.details
        "This action scans fastlane/metadata folder and uploads metadata to lokalise.co"
      end


      def self.available_options
        [
          FastlaneCore::ConfigItem.new(key: :platform,
                                       env_name: "FASTLANE_PLATFORM_NAME",
                                       description: "Fastlane platform name"),
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
          FastlaneCore::ConfigItem.new(key: :metadata_path,
                                       description: "Location where the metadata files should be stored and read from",
                                       optional: true),
          FastlaneCore::ConfigItem.new(key: :add_languages,
                                       description: "Add missing languages in lokalise",
                                       optional: true,
                                       is_string: false,
                                       default_value: false,
                                       verify_block: proc do |value|
                                         UI.user_error! "Add languages should be true or false" unless [true, false].include? value
                                       end),
          FastlaneCore::ConfigItem.new(key: :override_translation,
                                       description: "Override translations in lokalise",
                                       optional: true,
                                       is_string: false,
                                       default_value: false,
                                       verify_block: proc do |value|
                                         UI.user_error! "Override translation should be true or false" unless [true, false].include? value
                                       end),
          FastlaneCore::ConfigItem.new(key: :action,
                                       description: "Action to perform (download_from_lokalise, upload_to_lokalise)",
                                       optional: false,
                                       is_string: true,
                                       verify_block: proc do |value|
                                         UI.user_error! "Action should be one of the following: download_from_lokalise, upload_to_lokalise" unless ["download_from_lokalise", "upload_to_lokalise"].include? value
                                       end),
          FastlaneCore::ConfigItem.new(key: :release_number,
                                      description: "Release number is required for Android actions",
                                      optional: true,
                                      is_string: false),
        ]
      end


      def self.authors
        ["Fedya-L", "BasouKazuma"]
      end


      def self.is_supported?(platform)
        [:ios, :android, :mac].include? platform
      end


    end
  end
end
