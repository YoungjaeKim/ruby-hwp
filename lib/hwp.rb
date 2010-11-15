# coding: utf-8
# apt-get install libole-ruby
# or gem install ruby-ole
# (주)한글과컴퓨터의 한컴오피스 hwp 문서 파일 구조 공개정책에 따라 이루어졌습니다.
# 이렇게 말하면 ruby-hwp 개발자가 (주)한글과컴퓨터社와 어떤 관계가 있는 것처럼 오해받을 수 있지만
# hwp 스펙 문서 11쪽 저작권 관련 내용을 보면 이렇게 표시하라고 해서 이렇게 표시했을 뿐입니다.
# ruby-hwp는 (주)한글과컴퓨터社가 만든 것이 아니며, (주)한글과컴퓨터社가 지원하지 않으며, (주)한글과컴퓨터社가 유지보수하지 않습니다.
# Note that ruby-hwp is not manufactured, approved, supported, maintained by Hancom Inc.
# ruby-hwp 개발자는 (주)한글과컴퓨터社와 아무런 관련이 없습니다.
# ruby-hwp 및 ruby-hwp 관련 문서 내용을 사용하여 발생된 모든 결과에 대하여 책임지지 않습니다.
# NO WARRANTY

require 'iconv'
require 'ole/storage'
require 'zlib'
require 'stringio'
require 'hwp/model.rb'
require 'hwp/tags.rb'
##
require 'hwp/datatypes.rb'
require 'hwp/parser.rb'

module HWP
# unpack, pack
# C     |  Unsigned char # 1 byte
# I     |  Unsigned integer # 4 bytes
# L     |  Unsigned long
# S     |  Unsigned short # 2 bytes

# c     |  char # 1 byte
# i     |  integer # 4 bytes
# l     |  long
# s     |  short # 2 bytes

# unpack, pack
# C     |  UINT8  # 1 byte
# I     |  UINT32 # 4 bytes
# L     |  Unsigned long
# S     |  UINT16 # 2 bytes

# c     |  char # 1 byte
# i     |  integer # 4 bytes
# l     |  long
# s     |  short # 2 bytes

# typedef unsigned char  UINT8;		1 byte
# typedef unsigned short UINT16;	2 bytes
# typedef unsigned int   UINT32;	4 bytes

	BYTE = 1
	WORD = 2
	DWORD = 4
	WCHAR = 2
	HWPUNIT = 4
	SHWPUNIT = 4
	UINT8 = 1
	UINT16 = 2
	UINT32 = 4
	UINT = UINT32
	INT8 = 1
	INT16 = 2
	INT32 = 4
	HWPUNIT16 = 2
	COLORREF = 4

	def self.open file
		Document.new file
	end

	class Document
		attr_reader :entries, :header, :doc_info, :bodytext, :view_text,
					:summary_info, :bin_data, :prv_text, :prv_image,
					:doc_options, :scripts, :xml_template, :doc_history

		def initialize file
			@ole = Ole::Storage.open(file, 'rb')
			_entries = @ole.dir.entries('/') - ['.', '..']

			_ROOT_ELEMENTS = [ "FileHeader", "DocInfo", "BodyText", "ViewText",
						"\005HwpSummaryInformation", "BinData", "PrvText", "PrvImage",
						"DocOptions", "Scripts", "XMLTemplate", "DocHistory" ]

			# sorting by priority
			@entries = _ROOT_ELEMENTS - (_ROOT_ELEMENTS - _entries)

			@entries.each do |entry|
				dirent = @ole.dirent_from_path entry
				case entry
				when "FileHeader"	then @header = FileHeader.new dirent
				when "DocInfo"		then @doc_info = Record::DocInfo.new(dirent, @header)
				when "BodyText"		then @bodytext = Record::BodyText.new(dirent, @header)
				when "ViewText"		then @view_text = Record::ViewText.new dirent
				when "\005HwpSummaryInformation"
					@summary_info = Record::SummaryInformation.new dirent
				when "BinData"		then @bin_data = Record::BinData.new(dirent, @header)
				when "PrvText"		then @prv_text = Record::PrvText.new dirent
				when "PrvImage"		then @prv_image = Record::PrvImage.new dirent
				when "DocOptions"	then @doc_options = Record::DocOptions.new dirent
				when "Scripts"		then @scripts = Record::Scripts.new dirent
				when "XMLTemplate"	then @xml_template = Record::XMLTemplate.new dirent
				when "DocHistory"	then @doc_history = Record::DocHistory.new(dirent, @header)
				else raise "unknown entry"
				end
			end
		end

		def close
			@ole.close
		end

		def to_s
			@header.to_s		if defined? @header
			@doc_info.to_s		if defined? @doc_info
			@bodytext.to_s		if defined? @bodytext
			@view_text.to_s		if defined? @view_text
			@summary_info.to_s	if defined? @summary_info
			@bin_data.to_s		if defined? @bin_data
			@prv_text.to_s		if defined? @prv_text
			@prv_image.to_s		if defined? @prv_image
			@doc_options.to_s	if defined? @doc_options
			@scripts.to_s		if defined? @scripts
			@xml_template.to_s	if defined? @xml_template
			@doc_history.to_s	if defined? @doc_history
		end
	end

	class CommonCtrl
#	표		tbl
#	선		lin
#	사각형	rec
#	타원		ell
#	호		arc
#	다각형	pol
#	곡선		cur
#	한글97수식	eqed
#	그림			pic
#	ole			ole
#	묶음개체		con
	end

	class CommonProperty
#		@common_property # 36 bytes
		def initialize data
			str_io = StringIO.new data
			@ctrl_id = str_io.read(4)
			@property = str_io.read(4).unpack("b*")[0]
			@hoz_offset = str_io.read(4)
			@ver_offset = str_io.read(4)
			@width = str_io.read(4)
			@height = str_io.read(4)
			@z_order = str_io.read(2)
			@margins = str_io.read(2*4)
			@instance_id = str_io.read(4)
			@len = str_io.read(2)
			@chars = str_io.read(2*@len) # 끝까지 읽는다
		end
#		@caption_list # if any
	end
end

class FileHeader
	attr_accessor :signature, :version, :property, :reversed
	def initialize dirent
		data = dirent.read
		@signature	= data[0..31]
		@version	= data[32..35].reverse.unpack("C*").join(".")
		@property	= data[36..39].unpack("b*")[0]
		@reversed	= data[40..255]
	end

	method_names = ['gzipped?', 'encrypted?', 'distribute?', 'script?',
					'drm?', 'xmltemplate?', 'history?', 'sign?',
					'certificate_encrypt?', 'sign_spare?', 'certificate_drm?', 'ccl?']

	method_names.each_with_index do |method_name, i|
		define_method(method_name) do
			@property[i] == '1' ? true : false
		end
	end
end

module Record
	module Header
		def self.decode bytes
			lsb_first = bytes.unpack("b*")[0] # 이진수, LSB first, bit 0 가 맨 앞에 온다.

			if lsb_first
				@tag_id	= lsb_first[0..9].reverse.to_i(2) # 9~0
				@level	= lsb_first[10..19].reverse.to_i(2) # 19~10
				@size	= lsb_first[20..31].reverse.to_i(2) # 31~20
			end
		end

		def self.tag_id;	@tag_id;	end
		def self.level;		@level;		end
		def self.size;		@size;		end
	end

	class BodyText
		attr_accessor :sections
		def initialize(dirent, header)
			@dirent = dirent
			@sections = []

			if header.gzipped?
				@dirent.each_child do |section|
					z = Zlib::Inflate.new(-Zlib::MAX_WBITS)
					@sections << StringIO.new(z.inflate section.read)
					z.finish
					z.close
				end
			else
				@dirent.each_child do |section|
					@sections << StringIO.new(section)
				end
			end
		end
	end # of (class BodyText)

	class ViewText
		def initialize dirent
			raise NotImplementedError.new("ViewText is not supported")
		end
	end

	class SummaryInformation
	end

	class BinData
		def initialize(dirent, header);end
	end

	class PrvText
		def initialize(dirent)
			@dirent = dirent
		end

		def parse
			puts Iconv.iconv('utf-8', 'utf-16', @dirent.read)
		end
	end

	class PrvImage
		def initialize(dirent)
			@dirent = dirent
		end

		def parse
			p @dirent.read
		end
	end

	class DocOptions;end
	class Scripts;end
	class XMLTemplate;end

	class DocHistory
		def initialize(dirent, header);end
	end
end # of (module Record)
