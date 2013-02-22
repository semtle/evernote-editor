require 'evernote_oauth'
require 'fileutils'
require 'tempfile'
require "highline/import"
require "redcarpet"

module EvernoteEditor

  class Editor

    CONFIGURATION_FILE = File.expand_path("~/.evned")
    attr_accessor :configuration

    def initialize(*args, opts)
      @title   = args.flatten[0] || "Untitled note - #{Time.now}"
      @tags    = (args.flatten[1] || '').split(',')
      @options = opts
      @mkdout  = Redcarpet::Markdown.new(Redcarpet::Render::XHTML,
        autolink: true, space_after_headers: true, no_intra_emphasis: true)
    end

    def run
      configure
      @options[:edit] ? edit_note : create_note
    end


    def configure
      FileUtils.touch(CONFIGURATION_FILE) unless File.exist?(CONFIGURATION_FILE)
      @configuration = YAML::load(File.open(CONFIGURATION_FILE)) || {}
      store_key unless @configuration[:token]
      store_editor unless @configuration[:editor]
    end

    def create_note
      markdown = invoke_editor
      begin
        evn_client = EvernoteOAuth::Client.new(token: @configuration[:token], sandbox: @sandbox)
        note_store = evn_client.note_store
        note = Evernote::EDAM::Type::Note.new
        note.title = @title
        note.content = note_markup(markdown)
        created_note = note_store.createNote(@configuration[:token], note)
        say "Successfully created a new note (GUID: #{created_note.guid})"
      rescue Evernote::EDAM::Error::EDAMSystemException,
             Evernote::EDAM::Error::EDAMUserException,
             Evernote::EDAM::Error::EDAMNotFoundException => e
        graceful_failure(markdown, e)
      end
    end

    def graceful_failure(markdown, e)
      say "Sorry, an error occurred saving the note to Evernote (#{e.message})"
      say "Here's the markdown you were trying to save:"
      say ""
      say "--BEGIN--"
      say markdown
      say "--END--"
      say ""
    end

    def edit_note
      found_notes = search_notes
      return unless found_notes
      if found_notes.empty?
        say "No notes were found matching '#{@title}'"
        return
      end
      
      choose do |menu|
        menu.prompt = "Which note would you like to edit:"
        found_notes.each do |n|
          menu.choice("#{Time.at(n.updated/1000).strftime('%Y-%m-%d %H:%M')} #{n.title}") { puts n.inspect }
        end
        menu.choice("None") { puts "None!" }
      end

    end

    def search_notes(term = '')
      begin
        evn_client = EvernoteOAuth::Client.new(token: @configuration[:token], sandbox: @sandbox)
        note_store = evn_client.note_store
        note_filter = Evernote::EDAM::NoteStore::NoteFilter.new
        note_filter.words = term
        results = note_store.findNotes(@configuration[:token], note_filter, 0, 10).notes
      rescue Evernote::EDAM::Error::EDAMSystemException,
             Evernote::EDAM::Error::EDAMUserException,
             Evernote::EDAM::Error::EDAMNotFoundException => e
        say "Sorry, an error occurred saving the note to Evernote (#{e.message})"
        false
      end

    end

    def note_markup(markdown)
      res = <<-EOS
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE en-note SYSTEM "http://xml.evernote.com/pub/enml2.dtd">
        <en-note>
        #{@mkdout.render(markdown)}
        </en-note>
      EOS
      res
    end

    def invoke_editor(initial_content = "")
      file = Tempfile.new(['evned', '.markdown'])
      file.puts(initial_content)
      file.flush
      file.close(false)
      open_editor(file.path)
      content = File.read(file.path)
      file.unlink
      content
    end

    def open_editor(file_path)
      cmd = [@configuration[:editor], blocking_flag, file_path].join(' ')
      system(cmd) or raise SystemCallError, "`#{cmd}` gave exit status: #{$?.exitstatus}"
    end

    # Patterned from Pry
    def blocking_flag
      case File.basename(@configuration[:editor])
      when /^[gm]vim/
        '--nofork'
      when /^jedit/
        '-wait'
      when /^mate/, /^subl/
        '-w'
      end
    end


    def store_key
      say "You will need a developer token to use this editor."
      say "More information: http://dev.evernote.com/start/core/authentication.php#devtoken"
      token = ask("Please enter your developer token: ") { |q| q.default = "none" }
      @configuration[:token] = token
      write_configuration
    end

    def store_editor
      editor_command = ask("Please enter the editor command you would like to use: ") { |q| q.default = `which vim`.strip.chomp }
      @configuration[:editor] = editor_command
      write_configuration
    end

    def write_configuration
      File.open(CONFIGURATION_FILE, "w") do |file|
        file.write @configuration.to_yaml
      end
    end

    #"S=s1:U=b73d:E=144369d53e9:C=13cdeec27e9:P=1cd:A=en-devtoken:H=cae2b3fa91691e351744620de8ec0418"
  end

end
