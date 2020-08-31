# frozen_string_literal: true

require 'stamped_files'

def public_root
  "#{Rails.root}/public"
end

def public_js
  "#{public_root}/javascripts"
end

def vendor_js
  "#{Rails.root}/vendor/assets/javascripts"
end

def library_src
  "#{Rails.root}/node_modules"
end

def write_template(path, template)
  header = <<~HEADER
    // DO NOT EDIT THIS FILE!!!
    // Update it by running `rake javascript:update_constants`
  HEADER

  basename = File.basename(path)
  output_path = "#{Rails.root}/app/assets/javascripts/#{path}"

  File.write(output_path, "#{header}\n\n#{template}")
  puts "#{basename} created"
  %x{yarn run prettier --write #{output_path}}
  puts "#{basename} prettified"
end

task 'javascript:update_constants' => :environment do
  write_template("discourse/app/lib/constants.js", <<~JS)
    export const SEARCH_PRIORITIES = #{Searchable::PRIORITIES.to_json};

    export const SEARCH_PHRASE_REGEXP = '#{Search::PHRASE_MATCH_REGEXP_PATTERN}';
  JS

  write_template("pretty-text/addon/emoji/data.js", <<~JS)
    export const emojis = #{Emoji.standard.map(&:name).flatten.inspect};
    export const tonableEmojis = #{Emoji.tonable_emojis.flatten.inspect};
    export const aliases = #{Emoji.aliases.inspect.gsub("=>", ":")};
    export const searchAliases = #{Emoji.search_aliases.inspect.gsub("=>", ":")};
    export const translations = #{Emoji.translations.inspect.gsub("=>", ":")};
    export const replacements = #{Emoji.unicode_replacements_json};
  JS

  write_template("pretty-text/addon/emoji/version.js", <<~JS)
    export const IMAGE_VERSION = "#{Emoji::EMOJI_VERSION}";
  JS
end

task 'javascript:update' => :remove_stamped_files do
  require 'uglifier'

  yarn = system("yarn install")
  abort('Unable to run "yarn install"') unless yarn

  dependencies = [
    {
      source: 'bootstrap/js/modal.js',
      destination: 'bootstrap-modal.js'
    }, {
      source: 'ace-builds/src-min-noconflict/ace.js',
      destination: 'ace',
      public: true,
      stamp: true
    }, {
      source: 'chart.js/dist/Chart.min.js',
      public: true,
      stamp: true
    }, {
      source: 'chartjs-plugin-datalabels/dist/chartjs-plugin-datalabels.min.js',
      public: true,
      stamp: true
    }, {
      source: 'magnific-popup/dist/jquery.magnific-popup.min.js',
      public: true,
      stamp: true
    }, {
      source: 'pikaday/pikaday.js',
      public: true,
      stamp: true
    }, {
      source: 'spectrum-colorpicker/spectrum.js',
      uglify: true,
      public: true,
      stamp: true
    }, {
      source: 'spectrum-colorpicker/spectrum.css',
      public: true
    }, {
      source: 'favcount/favcount.js'
    }, {
      source: 'handlebars/dist/handlebars.js'
    }, {
      source: 'handlebars/dist/handlebars.runtime.js'
    }, {
      source: 'highlight.js/build/.',
      destination: 'highlightjs'
    }, {
      source: 'jquery-resize/jquery.ba-resize.js'
    }, {
      source: 'jquery.autoellipsis/src/jquery.autoellipsis.js',
      destination: 'jquery.autoellipsis-1.0.10.js'
    }, {
      source: 'jquery-color/dist/jquery.color.js'
    }, {
      source: 'jquery.cookie/jquery.cookie.js'
    }, {
      source: 'blueimp-file-upload/js/jquery.fileupload.js',
    }, {
      source: 'blueimp-file-upload/js/jquery.iframe-transport.js',
    }, {
      source: 'blueimp-file-upload/js/vendor/jquery.ui.widget.js',
    }, {
      source: 'jquery/dist/jquery.js'
    }, {
      source: 'jquery-tags-input/src/jquery.tagsinput.js'
    }, {
      source: 'markdown-it/dist/markdown-it.js'
    }, {
      source: 'mousetrap/mousetrap.js'
    }, {
      source: 'moment/moment.js'
    }, {
      source: 'moment/locale/.',
      destination: 'moment-locale',
    }, {
      source: 'moment-timezone/builds/moment-timezone-with-data-10-year-range.js',
      destination: 'moment-timezone-with-data.js'
    }, {
      source: 'lodash.js',
      destination: 'lodash.js'
    }, {
      source: 'moment-timezone-names-translations/locales/.',
      destination: 'moment-timezone-names-locale'
    }, {
      source: 'mousetrap/plugins/global-bind/mousetrap-global-bind.js'
    }, {
      source: 'resumablejs/resumable.js'
    }, {
      # TODO: drop when we eventually drop IE11, this will land in iOS in version 13
      source: 'intersection-observer/intersection-observer.js'
    }, {
      source: 'workbox-sw/build/.',
      destination: 'workbox',
      public: true,
      stamp: true
    }, {
      source: 'workbox-routing/build/.',
      destination: 'workbox',
      public: true,
      stamp: true
    }, {
      source: 'workbox-core/build/.',
      destination: 'workbox',
      public: true,
      stamp: true
    }, {
      source: 'workbox-strategies/build/.',
      destination: 'workbox',
      public: true,
      stamp: true
    }, {
      source: 'workbox-expiration/build/.',
      destination: 'workbox',
      public: true,
      stamp: true
    }, {
      source: '@popperjs/core/dist/umd/popper.js'
    }, {
      source: '@popperjs/core/dist/umd/popper.js.map',
      public_root: true
    },
    {
      source: 'route-recognizer/dist/route-recognizer.js'
    }, {
      source: 'route-recognizer/dist/route-recognizer.js.map',
      public_root: true
    },

  ]

  start = Time.now

  dependencies.each do |f|
    src = "#{library_src}/#{f[:source]}"

    unless f[:destination]
      filename = f[:source].split("/").last
    else
      filename = f[:destination]
    end

    # Highlight.js needs building
    if src.include? "highlight.js"
      puts "Install Highlight.js dependencies"
      system("cd node_modules/highlight.js && yarn install")

      puts "Build Highlight.js"
      system("cd node_modules/highlight.js && node tools/build.js -t cdn none")

      puts "Cleanup unused styles folder"
      system("rm -rf node_modules/highlight.js/build/styles")

      langs_dir = 'vendor/assets/javascripts/highlightjs/languages/*.min.js'

      # We don't need every language for tests
      langs = ['javascript', 'sql', 'ruby']
      test_bundle_dest = 'vendor/assets/javascripts/highlightjs/highlight-test-bundle.min.js'
      File.write(test_bundle_dest, HighlightJs.bundle(langs))
    end

    if f[:public_root]
      dest = "#{public_root}/#{filename}"
    elsif f[:public]
      dest = "#{public_js}/#{filename}"
    else
      dest = "#{vendor_js}/#{filename}"
    end

    if src.include? "ace.js"
      ace_root = "#{library_src}/ace-builds/src-min-noconflict/"
      addtl_files = [ "ext-searchbox", "mode-html", "mode-scss", "mode-sql", "theme-chrome", "worker-html"]
      FileUtils.mkdir(dest) unless File.directory?(dest)
      addtl_files.each do |file|
        FileUtils.cp_r("#{ace_root}#{file}.js", dest)
      end
    end

    # lodash.js needs building
    if src.include? "lodash.js"
      puts "Building custom lodash.js build"
      system('yarn run lodash include="each,filter,map,range,first,isEmpty,chain,extend,every,omit,merge,union,sortBy,uniq,intersection,reject,compact,reduce,debounce,throttle,values,pick,keys,flatten,min,max,isArray,delay,isString,isEqual,without,invoke,clone,findIndex,find,groupBy" minus="template" -d -o "node_modules/lodash.js"')
    end

    unless File.exists?(dest)
      STDERR.puts "New dependency added: #{dest}"
    end

    if f[:uglify]
      File.write(dest, Uglifier.new.compile(File.read(src)))
    else
      FileUtils.cp_r(src, dest)
    end

    # NOTE: Once we're confident there are no hardcoded calls to non-stamped filenames
    #       we can remove this step, and simply replace the dest for stamp'ed files
    if f[:stamp]
      stamped = "#{public_js}/#{StampedFiles.update_filename(filename)}"
      FileUtils.copy_entry(dest, stamped)
    end
  end

  puts "git_hash REVISION: #{StampedFiles.git_hash}"
  File.write(StampedFiles.revision_filename, StampedFiles.git_hash)

  STDERR.puts "Completed copying dependencies: #{(Time.now - start).round(2)} secs"
end

task 'javascript:remove_stamped_files' do
  revisions_to_keep = 0

  if ENV['REVISIONS_TO_KEEP']
    if ENV['REVISIONS_TO_KEEP'].to_i.to_s != ENV['REVISIONS_TO_KEEP']
      raise 'javascript:remove_stamped_files - REVISIONS_TO_KEEP must be an integer'
    else
      revisions_to_keep = ENV['REVISIONS_TO_KEEP'].to_i
    end
  end

  StampedFiles.cleanup(revisions_to_keep) unless Rails.env.test?
end
