require 'pp'
require 'fileutils'
require 'zip/zip'
require 'tmpdir'

module Neurogami
  class EpubNg

    include FileUtils

    def initialize 
      @file_ids = {}
      @calling_dir = Dir.pwd
    end

    def file_id file
      if @file_ids[file] 
        @file_ids[file]
      else
        fid = file.gsub '/', '__'
        fid.gsub! '.', '_'
        if @file_ids.keys.include? fid 
          raise "Failed to generate unique ID for '#{file}'"
        else
          @file_ids[file] = fid
        end
        @file_ids[file]
      end
    end

    def make_metadata  h
     %~<package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="BookID">
    <metadata xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:opf="http://www.idpf.org/2007/opf">
     <dc:title>#{h[:title]}</dc:title> 
     <dc:creator opf:role="aut">#{h[:author]}</dc:creator>
     <dc:language>en-US</dc:language> 
     <dc:rights>#{h[:rights]}</dc:rights> 
     <dc:publisher>#{h[:publisher]}</dc:publisher> 
     <dc:identifier id="BookID" opf:scheme="UUID">#{h[:uuid]}</dc:identifier>
     </metadata>
     ~
    end

    def media_type file
      # Why not have a hash? 
      ext = file.split('.').last
      case ext
      when 'html', 'xhtml', 'xml'
          'application/xhtml+xml'
      when 'css'
          'text/css'
      when 'png'
        'image/png'
      when 'jpg'
        'image/jpg'
      when 'ncx'
        'application/x-dtbncx+xml'
      when 'xpgt'
        'application/vnd.adobe-page-template+xml'
      else
        raise "Unknown file type in media_type for file '#{file}'"
      end
    end

    def make_manifest file_list
      raise "Cannot have a manifest with an empty file list!" if file_list.empty?
      # File paths needs to be relative to @doc_root_folder
      m = %~<manifest>
        <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml" />
      ~  

      file_list.sort.each do |file|
        p file
        next unless File.file? "#{@doc_root_folder}/#{file}"
        next if file =~ /\.opf$/
        next if file =~ /toc\.ncx$/
        @file_ids[file] = file_id file

        raise "@file_ids still empty after adding new ID #{@file_ids.pretty_inspect}" if @file_ids.empty?
        m << %~<item id="#{@file_ids[file]}" href="#{file}" media-type="#{media_type file}" />\n~
      end

      m << %~</manifest>~
    end

    def title_from_file_name f
      file = f.split('/').last
      file = f.split('.').first
      file.gsub! '_', ' '
      file.titlecase #   .capitalize  
    end

    def make_spine
      @spine_ids = []
      # Sort (x)html files by name and add.
      # Make special allowances for files matching /^title/ and /^copyright/

      title_page = nil
      copyright_page = nil
      legal_page = nil
      cover_page = nil
      text_file_ids = []

      @file_ids.keys.sort.each do |f| 
        file_name = f.split('/').last

        next unless file_name =~ /html$/

        if file_name =~ /^copyright/i
          copyright_page = @file_ids[f]
          nil
        elsif file_name =~ /^title/i
          title_page = @file_ids[f]
          nil
        elsif file_name =~ /^cover/i
          cover_page = @file_ids[f]
          nil
        elsif file_name =~ /^legal/i
          legal_page = @file_ids[f]
          nil
        else
          if file_name =~ /html$/i
            text_file_ids << @file_ids[f]
          end
        end

      end

      s =  %~ <spine toc="ncx">\n~
      if cover_page
        s << %~ <itemref idref="#{cover_page}" linear="no" />\n~
        @spine_ids << cover_page
      end

      if title_page
        s << %~ <itemref idref="#{title_page}" />\n~
        @spine_ids << title_page
      end

      if copyright_page
        s << %~ <itemref idref="#{copyright_page}" />\n~
        @spine_ids << copyright_page
      end

      text_file_ids.each do |id|
        s << %~ <itemref idref="#{id}" />\n~
        @spine_ids << id
      end

      if legal_page
        s << %~ <itemref idref="#{legal_page}" />\n~
        @spine_ids << legal_page
      end

      s << %~</spine>~

    end


    def file_from_file_id id 
      file = nil
      @file_ids.each do |k, v|
        if v == id
          file =  k
        end
      end
      file
    end

    def title_from_file_id id
      title = nil
      @file_ids.each do |k, v|
        if v == id
          title = title_from_file_name k
        end
      end
      title
    end

    def make_toc 
      toc  =%~<?xml version="1.0" encoding="UTF-8"?>
 <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
 <head>
    <meta name="dtb:uid" content="#{@metadata_hash[:uuid]}"/>
    <meta name="dtb:depth" content="1"/>
    <meta name="dtb:totalPageCount" content="#{@spine_ids.size}"/> <!-- FIXME -->
    <meta name="dtb:maxPageNumber" content="#{@spine_ids.size}"/> <!-- FIXME -->
 </head>

 <docTitle>
    <text>#{@metadata_hash[:title]}</text>
 </docTitle>
~

      toc << %~<navMap>\n~

      @spine_ids.each_with_index do |id, idx|
        title = title_from_file_id id
        file = file_from_file_id id
        toc << %~<navPoint id="#{id}" playOrder="#{idx+1}">
        <navLabel>
            <text>#{title}</text>
        </navLabel>
        <content src="#{file}"/>
    </navPoint>\n~
      end

      toc << %~</navMap>
</ncx>~

    end

    def make_file_list
      @file_list = Dir.glob "#{@doc_root_folder}/**/*"
      @file_list.reject! { |f| File.directory? f }
      @file_list.map!{|f| f.sub( "#{@doc_root_folder}/", '') }
      @file_list.reject! {|f| f =~ /\.(js|ico|gif|txt)$/i }
      @file_list
    end

    def process epub_file_name, doc_root_folder, metadata_hash
      @file_ids = {}
      @metadata_hash = metadata_hash
      @doc_root_folder = doc_root_folder
      @doc_root_folder.sub! /\/$/, ''
      @epub_file_name = epub_file_name

      metadata = make_metadata @metadata_hash

      make_file_list

      raise "Empty @file_list" if @file_list.empty?

      manifest = make_manifest @file_list
      spine = make_spine
      toc = make_toc
      content = %~<?xml version="1.0" encoding="UTF-8"?>\n#{metadata}\n#{manifest}\n#{spine}\n</package>~
      create_epub content, toc, @doc_root_folder
      check @epub_file_name  
    end

    def check epub_file_name  
      cmd = 'java -jar /home/james/data/vendor/epubcheck-3.0b5/epubcheck-3.0b5.jar'
      results =  `#{cmd} #{epub_file_name  }`
      puts results
    end

    def make_container
%~<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
    <rootfiles>
        <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
   </rootfiles>
</container>~
    end

    def create_epub content, toc, doc_root_folder

      outfile_path = @calling_dir + '/' + @epub_file_name
      if File.exist? outfile_path 
        File.unlink outfile_path 
      end

      Dir.mktmpdir("epub_") do |dir|
        Dir.chdir dir do 
          
          FileUtils.mkdir "OEBPS"

          @file_list.each do |f|
            dirpath  = File.dirname f
            FileUtils.mkdir_p 'OEBPS/'+dirpath
            src = doc_root_folder +'/'+f
            dest = 'OEBPS/'+f
            FileUtils.cp src, dest
          end

          FileUtils.mkdir "META-INF" 

          File.open( 'META-INF/container.xml', 'wb') do |f|
            f.puts make_container
          end

          File.open( 'OEBPS/content.opf', 'wb') do |f|
            f.puts content
          end

          File.open( 'OEBPS/toc.ncx', 'wb') do |f|
            f.puts toc
          end

          Zip::ZipOutputStream::open outfile_path do |o|
            o.put_next_entry "mimetype", nil, nil, Zip::ZipEntry::STORED, Zlib::NO_COMPRESSION
            o << "application/epub+zip"
          end

          z = Zip::ZipFile.open outfile_path  

          Dir.glob( '**/*' ).each do |path|
            next unless File.file? path
            p path
            z.add path, path
          end

          z.commit

        end
      end 
    end

    def help
      txt = %~
There's no proper CLI support right now.  

Code usage is this:

  require 'epub-ng'
  e = Neurogami::EpubNg.new
  mh = {
    :title => "Sample Book",
    :author => "Will Shakespear",
    :rights => "Copyright 2012 Will Shakespear",
    :publisher => "Just the Best Parts",
    :uuid => "samplebook"
  }
      
  e.process "your-ebook-name.epub", "/path/to/root/folder/holding/book/file", mh

The code assumes that folder of files has everything requred, in proper format.

You can generate epub content source files using any number of static Web site generation tools, such as nanoc.

epub-ng  grabs those files and creates the needed metadata files and creates the epub file itself.

There are some naming conventions used to sort and place various content files.

Best to look at the code for that, but basically TOC is based on alphabetical order.
      
James Britt
      ~ 
      puts txt
    end
  end
end

__END__

Notes:

The code assumes that you have already generate all the book content files somehow,
e.g. using Webby  or some other HTML generation tool.

Naming conventions are used.  Content files with names matching ^cover, ^title, 
and ^legal get special treatment when generating the spine and TOC.

Otherwise content files are ordered alphabetically.

You'll need to edit the code to change what jar file is used to run the epub
checker. :)







