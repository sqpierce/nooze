# Note: most of the code is encapsulated in a class, but this is an executable script.
# Example: cron could run as 'ruby nooze.rb'

require "redis"
require "open-uri"
require "zip"
require "fileutils"
require "digest"

class Nooze

    REDIS_NEWS_LIST = 'NEWS_XML'.freeze
    REDIS_ZIP_FILE_SET = 'NEWS_ZIP_FILES'.freeze
    REDIS_XML_FILE_SET = 'NEWS_XML_FILES'.freeze
    DEBUG = true # set to false for non-verbose logging

    attr_reader :config, :redis

    def initialize(config)
        @config = config
        log "running with #{config.inspect}"
        @redis = Redis.new(:url => config[:redis_uri])
    end

    def run
        fetch_zip_file_paths.each do |url, file_name|
            fetch_one_zip_file(url, file_name)
            process_one_zip_file(file_name)
        end
    end

    private

    def fetch_zip_file_paths
        # scrape html for current file list
        zip_file_hash = {}
        begin
            log "fetching from #{config[:file_uri]}"
            open(config[:file_uri]) do |f|
                f.each_line do |line|
                    match = line.match /href=\"(.*?\/(\d+.zip))\"/
                    if match && !redis.sismember(REDIS_ZIP_FILE_SET, match[2])
                        log("processing: #{match[1]}")
                        zip_file_hash[match[1]] = match[2] # { url => file_name }
                    elsif match
                        log("skipping: #{match[1]}")
                    end
                end
            end
        rescue => e
            # not much point carrying on in this case, as it's likely a uri or redis connect issue
            log_error("ERROR in fetch_file_list: +#{e.inspect}", exit_app: true)
        end
        zip_file_hash
    end

    def fetch_one_zip_file(url, file_name)
        # download zip file to directory based on configuration
        log "#{url}: #{file_name}"
        begin
            open(url) do |zip|
                # note: this assumes we'll take care to make sure only one instance of this script is running at a time
                # otherwise we could create a tmp working dir based on timestamp or something.
                File.open("#{config[:working_dir]}/#{file_name}","wb") do |file|
                    file.puts zip.read
                end
            end
        rescue => e
            log_error("ERROR for #{url}:#{file_name} in fetch_one_zip_file: +#{e.inspect}")
        end
    end

    def process_one_zip_file(file_name)
        working_zip_file = "#{config[:working_dir]}/#{file_name}"
        destination = working_zip_file.gsub(/\.zip$/, '')
        begin
            extract_zip(working_zip_file, destination)
            # interate through dir and process each xml file contained therein...
            Dir.entries(destination).each do |f|
                next if f.match /^\./
                md5hash = f.sub(/\.xml$/, '')
                xml_file = "#{destination}/#{f}"
                # check redis set to see if we've already dealt with this news article by checking md5 hash
                unless redis.sismember(REDIS_XML_FILE_SET, md5hash)
                    log("processing xml file: #{xml_file}")
                    # note: once we know we can rely on file name to be hash of contents, we don't have to care about this.
                    # this does in fact seem to check out.
                    #log("validate hash: #{Digest::MD5.file(xml_file) == md5hash}")

                    # get file contents and write to redis list in transaction together with md5 hash to set
                    contents = File.open(xml_file, 'rb') { |f| f.read }
                    redis.multi do
                        redis.lpush(REDIS_NEWS_LIST, contents)
                        redis.sadd(REDIS_XML_FILE_SET, md5hash)
                    end
                end
            end
            redis.sadd(REDIS_ZIP_FILE_SET, file_name)
            processed_zip_file = "#{config[:processed_dir]}/#{file_name}"
            File.rename(working_zip_file, processed_zip_file)
            FileUtils.rm_rf(destination)
        rescue => e
            log_error("ERROR for #{file_name} whilst processing zip: +#{e.inspect}")
        end
    end

    def log_error(err, exit_app: false)
        # do something clever with error... what are the requirements here?
        # could have redirect output to appropriate place.
        STDERR.puts err
        exit! if exit_app
    end

    def log(log_msg)
        # what are the requirements here?
        # this will be STDOUT and can be dealt with by cron, etc.
        puts log_msg if DEBUG
    end

    # helper method stolen from here: http://stackoverflow.com/questions/19754883/how-to-unzip-a-zip-file-containing-folders-and-files-in-rails-while-keeping-the
    def extract_zip(file, destination)
      FileUtils.mkdir_p(destination)

      Zip::File.open(file) do |zip_file|
        zip_file.each do |f|
          fpath = File.join(destination, f.name)
          zip_file.extract(f, fpath) unless File.exist?(fpath)
        end
      end
    end
end

test_config = {
    file_uri: "#{Dir.pwd}/files/feed_source_testing.html",
    redis_uri: "redis://localhost:6379/0",
    working_dir: "working",
    processed_dir: "processed"
}

production_config = {
    file_uri: "http://feed.omgili.com/5Rh5AMTrc4Pv/mainstream/posts/",
    redis_host: "redis://localhost:6379/1", # correct this if needed
    working_dir: "working",
    processed_dir: "processed"
}

nooze = Nooze.new(test_config) # replace with production_config when running in production

nooze.run
