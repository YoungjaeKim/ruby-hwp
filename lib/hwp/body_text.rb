# coding: utf-8
#
# body_text.rb
#
# Copyright (C) 2010-2012  Hodong Kim <cogniti@gmail.com>
# 
# ruby-hwp is free software: you can redistribute it and/or modify it
# under the terms of the GNU Lesser General Public License as published
# by the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# ruby-hwp is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See the GNU Lesser General Public License for more details.
# 
# You should have received a copy of the GNU Lesser General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# 한글과컴퓨터의 한/글 문서 파일(.hwp) 공개 문서를 참고하여 개발하였습니다.

require 'hwp/utils'
require 'pp'

module Record::Section
    class ParaHeader
        attr_reader :chars,
                    :control_mask,
                    :para_shape_id,
                    :para_style_id,
                    :column_type,
                    :num_char_shape,
                    :num_range_tag,
                    :num_align,
                    :para_instance_id,
                    :level
        attr_accessor :para_text,
                      :para_char_shapes,
                      :para_line_segs,
                      :ctrl_headers,
                      :table

        def initialize context
            @level = context.level
            @chars,
            @control_mask,
            @para_shape_id,
            @para_style_id,
            @column_type,
            @num_char_shape,
            @num_range_tag,
            @num_align,
            @para_instance_id = context.data.unpack("vVvvvvvvV")

            # para_text, para_char_shape 가 1개 밖에 안 오는 것 같으나 확실하지 않으니
            # 배열로 처리한다. 추후 ParaText, ParaCharShape 클래스를 ParaHeader 이나
            # 이와 유사한 자료구조(예를 들면, Paragraph)에 내포하는 것을 고려한다.
            @para_char_shapes = []
            @para_line_segs = []
            @ctrl_headers = []
            parse(context)
        end

        def parse(context)
            while context.has_next?
                context.stack.empty? ? context.pull : context.stack.pop

                if  context.level <= @level
                    context.stack << context.tag_id
                    break
                end

                case context.tag_id
                when HWPTAG::PARA_TEXT
                    @para_text = ParaText.new(context)
                when HWPTAG::PARA_CHAR_SHAPE
                    @para_char_shapes << ParaCharShape.new(context)
                when HWPTAG::PARA_LINE_SEG
                    @para_line_segs << ParaLineSeg.new(context)
                when HWPTAG::CTRL_HEADER
                    @ctrl_headers << CtrlHeader.new(context)
                #when HWPTAG::MEMO_LIST
                #    # TODO
                # table, memo_list 에서 HWPTAG::LIST_HEADER 가 온다.
                #when HWPTAG::LIST_HEADER
                #    if context.level <= @level
                #        context.stack << context.tag_id
                #        break
                #    else
                #        #raise "unhandled " + context.tag_id.to_s
                #    end
                # HWPTAG::SHAPE_COMPONENT
                #  HWPTAG::LIST_HEADER
                #  HWPTAG::PARA_HEADER
                #   HWPTAG::PARA_TEXT
                #   HWPTAG::PARA_CHAR_SHAPE
                #   HWPTAG::PARA_LINE_SEG
                #  HWPTAG::SHAPE_COMPONENT_RECTANGLE
                #when HWPTAG::SHAPE_COMPONENT_RECTANGLE
                #    if context.level <= @level
                #        context.stack << context.tag_id
                #        break
                #    else
                #        raise "unhandled " + context.tag_id.to_s
                #    end
                #when HWPTAG::DOC_INFO_32
                else
                    raise "unhandled " + context.tag_id.to_s
                end
            end
        end
        private :parse

        def to_text
            para_text.to_s
        end

        def to_layout doc
            section_def = doc.body_text.paragraphs[0].ctrl_headers[0].section_defs[0]
            page_def = section_def.page_defs[0]
            pango_context = Gdk::Pango.context
            desc = Pango::FontDescription.new("Sans 10")
            pango_context.load_font(desc)

            layout = Pango::Layout.new pango_context
            layout.width = (page_def.width - page_def.left_margin - page_def.
                right_margin) / 100.0 * Pango::SCALE
            layout.wrap = Pango::WRAP_WORD_CHAR
            layout.alignment = Pango::ALIGN_LEFT
            layout.text = @para_text.to_s
            layout
        end

        def to_tag
            "HWPTAG::PARA_HEADER"
        end

        def debug
            puts "\t"*@level + "ParaHeader:"
        end
    end

    class ParaText
        attr_reader :level

        def initialize context
            @level = context.level
            s_io = StringIO.new context.data
            @bytes = []
            while(ch = s_io.read(2))
                case ch.unpack("v")[0]
                # 2-byte control string
                when 0,10,13,24,25,26,27,28,29,31
                    #@bytes << ch.unpack("v")[0]
                when 30 # 0x1e record separator (RS)
                    @bytes << 0x20 # 임시로 스페이스로 대체

                # 16-byte control string, inline
                when 4,5,6,7,8,19,20
                    s_io.pos += 14
                when 9 # tab
                    @bytes << 9
                    s_io.pos += 14

                # 16-byte control string, extended
                when 1,2,3,11,12,14,15,16,17,18,21,22,23
                    ctrl_id = s_io.read(4).reverse
                    s_io.pos += 10
                    index = @bytes.size # FIXME
                    #raise if ctrl_index != [0,0]
                    #ctrl_ch = s_io.read(2).unpack("v")[0]
                    #p [ctrl_id, ctrl_index, ctrl_ch]
                # TODO mapping table
                # 유니코드 문자 교정, 한자 영역 등의 다른 영역과 겹칠지도 모른다.
                # L filler utf-16 값 "_\x11"
                when 0xf784 # "\x84\xf7
                    @bytes << 0x115f
                # V ㅘ       utf-16 값 "j\x11"
                when 0xf81c # "\x1c\xf8"
                    @bytes << 0x116a
                # V ㅙ       utf-16 값 "k\x11"
                when 0xf81d # "\x1d\xf8"
                    @bytes << 0x116b
                # V ㅝ       utf-16 값 "o\x11"
                when 0xf834 # "\x34\xf8" "4\xf8"
                    @bytes << 0x116f
                # T ㅆ       utf-16 값 "\xBB\x11"
                when 0xf8cd # "\xcd\xf8"
                    @bytes << 0x11bb
                else
                    @bytes << ch.unpack("v")[0]
                end
            end
            s_io.close
        end

        def to_s
            @bytes.pack("U*")
        end

        def to_tag
            "HWPTAG::PARA_TEXT"
        end

        def debug
            puts "\t"*@level +"ParaText:" + to_s
        end
    end # class ParaText

    class ParaCharShape
        attr_accessor :m_pos, :m_id, :level
        # TODO m_pos, m_id 가 좀 더 편리하게 바뀔 필요가 있다.
        def initialize context
            @level = context.level
            @m_pos, @m_id = [], []
            n = context.data.bytesize / 4
            context.data.unpack("V" * n).each_with_index do |element, i|
                @m_pos << element if (i % 2) == 0
                @m_id  << element if (i % 2) == 1
            end
        end

        def to_tag
            "HWPTAG::PARA_CHAR_SHAPE"
        end

        def debug
            puts "\t"*@level +"ParaCharShape:" + @m_pos.to_s + @m_id.to_s
        end
    end

    # TODO REVERSE-ENGINEERING
    # 스펙 문서에는 생략한다고 나와 있다. hwp3.0 또는 hwpml 스펙에 관련 정보가
    # 있는지 확인해야 한다.
    class ParaLineSeg
        attr_reader :level

        def initialize context
            @level = context.level
            @data  = context.data
        end

        def to_tag
            "HWPTAG::PARA_LINE_SEG"
        end

        def debug
            puts "\t"*@level +"ParaLineSeg:"
        end
    end

    class ParaRangeTag
        attr_accessor :start, :end, :tag, :level
        def initialize context
            @level = context.level
            raise NotImplementedError.new "Record::Section::ParaRangeTag"
            #@start, @end, @tag = data.unpack("VVb*")
        end
    end

    # TODO REVERSE-ENGINEERING
    class CtrlHeader
        include HWP::Utils

        attr_reader :ctrl_id, :level, :data
        attr_accessor :section_defs, :list_headers, :para_headers, :tables,
                      :eq_edits

        def initialize context
            @data = context.data
            @level = context.level
            s_io = StringIO.new context.data
            @ctrl_id = s_io.read(4).reverse

            @section_defs, @list_headers, @para_headers = [], [], []
            @tables, @eq_edits = [], []

            common = ['tbl ','$lin','$rec','$ell','$arc','$pol',
                      '$cur','eqed','$pic','$ole','$con']

            begin
                if common.include? @ctrl_id
                    bit = s_io.read(4).unpack("b32")
                    v_offset = s_io.read(4).unpack("V")
                    h_offset = s_io.read(4).unpack("V")
                    width = s_io.read(4).unpack("V")
                    height = s_io.read(4).unpack("V")
                    z = s_io.read(4).unpack("i")
                    margins = s_io.read(2*4).unpack("v*")
                    id = s_io.read(4).unpack("V")[0]
                    len = s_io.read(2).unpack("v")[0]
                    # 바이트가 남는다.
                    s_io.close
                end
            rescue => e
                STDERR.puts e.message
            end

            parse(context)
        end

        def parse(context)
            # ctrl id 에 따른 모델링과 그외 처리
            case @ctrl_id
            # 54쪽 표116 그외 컨트롤
            when "secd" # 구역 정의
                # TODO SectionDef 위치: 현재는 ctrl_header 에 위치하는데
                # 적절한 곳에 위치시킬 필요가 있다.
                secd = HWP::Model::SectionDef.new(self)
                secd.parse(context)
                @section_defs << secd
            when "cold" # 단 정의
                cold = HWP::Model::ColumnDef.new(self)
            when "head" # 머리말 header
                head = HWP::Model::Header.new(self)
                head.parse(context)
            when "foot" # 꼬리말 footer
                foot = HWP::Model::Footer.new(self)
                foot.parse(context)
            when "fn  " # 각주
                footnote = HWP::Model::Footnote.new(self)
                footnote.parse(context)
            when "en  " then raise NotImplementedError.new @ctrl_id
            when "atno" # 자동 번호
                atno = HWP::Model::AutoNum.new(self)
                return
            when "nwno" # 새 번호 지정
                nwno = HWP::Model::NewNum.new(self)
                return
            when "pghd" # 감추기 page hiding
                pghd = HWP::Model::PageHiding.new(self)
                return
            when "pgct" then raise NotImplementedError.new @ctrl_id
            when "pgnp" then raise NotImplementedError.new @ctrl_id
            when "idxm" then raise NotImplementedError.new @ctrl_id
            when "bokm" then raise NotImplementedError.new @ctrl_id
            when "tcps" # 글자 겹침 text compose 170쪽
                tcps = HWP::Model::TextCompose.new(self)
                return
            when "tdut" then raise NotImplementedError.new @ctrl_id
            when "tcmt" then raise NotImplementedError.new @ctrl_id
            # 41쪽 표62 개체 공통 속성을 포함하는 컨트롤
            when 'tbl '
                table = HWP::Model::Table.new(self)
                table.parse(context)
                @tables << table
            when 'gso '
                gso = HWP::Model::ShapeComponent.new(self)
                gso.parse(context)
            when 'form'
                form = HWP::Model::FormObject.new(self)
                form.parse context
            when '$lin' then raise NotImplementedError.new @ctrl_id
            when '$rec' then raise NotImplementedError.new @ctrl_id
            when '$ell' then raise NotImplementedError.new @ctrl_id
            when '$arc' then raise NotImplementedError.new @ctrl_id
            when '$pol' then raise NotImplementedError.new @ctrl_id
            when '$cur' then raise NotImplementedError.new @ctrl_id
            when 'eqed'
                eqed = HWP::Model::EqEdit.new(self)
                # 자식은 없으나 EQEDIT 레코드를 가지고 와야 한다.
                eqed.parse context
            when '$pic' then raise NotImplementedError.new @ctrl_id
            when '$ole' then raise NotImplementedError.new @ctrl_id
            when '$con' then raise NotImplementedError.new @ctrl_id
            # 54쪽 표116 필드 시작 컨트롤
            when "%unk" # FIELD_UNKNOWN
                # TODO
            when "%dte" then raise NotImplementedError.new @ctrl_id
            when "%ddt" then raise NotImplementedError.new @ctrl_id
            when "%pat" then raise NotImplementedError.new @ctrl_id
            when "%bmk" then raise NotImplementedError.new @ctrl_id
            when "%mmg" then raise NotImplementedError.new @ctrl_id
            when "%xrf" then raise NotImplementedError.new @ctrl_id
            when "%fmu" then raise NotImplementedError.new @ctrl_id
            when "%clk" # FIELD_CLICKHERE
                clk = HWP::Model::ClickHere.new(self)
                # 자식은 없으나 EQEDIT 레코드를 가지고 와야 한다.
                #eqed.parse context
            when "%smr" then raise NotImplementedError.new @ctrl_id
            when "%usr" then raise NotImplementedError.new @ctrl_id
            when "%hlk" # FIELD_HYPERLINK
            when "%sig" then raise NotImplementedError.new @ctrl_id
            when "%%*d" then raise NotImplementedError.new @ctrl_id
            when "%%*a" then raise NotImplementedError.new @ctrl_id
            when "%%*C" then raise NotImplementedError.new @ctrl_id
            when "%%*S" then raise NotImplementedError.new @ctrl_id
            when "%%*T" then raise NotImplementedError.new @ctrl_id
            when "%%*P" then raise NotImplementedError.new @ctrl_id
            when "%%*L" then raise NotImplementedError.new @ctrl_id
            when "%%*c" then raise NotImplementedError.new @ctrl_id
            when "%%*h" then raise NotImplementedError.new @ctrl_id
            when "%%*A" then raise NotImplementedError.new @ctrl_id
            when "%%*i" then raise NotImplementedError.new @ctrl_id
            when "%%*t" then raise NotImplementedError.new @ctrl_id
            when "%%*r" then raise NotImplementedError.new @ctrl_id
            when "%%*l" then raise NotImplementedError.new @ctrl_id
            when "%%*n" then raise NotImplementedError.new @ctrl_id
            when "%%*e" then raise NotImplementedError.new @ctrl_id
            when "%spl" then raise NotImplementedError.new @ctrl_id
            when "%%mr" then raise NotImplementedError.new @ctrl_id
            when "%%me" then raise NotImplementedError.new @ctrl_id
            when "%cpr" then raise NotImplementedError.new @ctrl_id
            else
                raise "unhandled #{@ctrl_id}"
            end

            # 다음 레코드 처리
            while context.has_next?
                context.stack.empty? ? context.pull : context.stack.pop

                if  context.level <= @level
                    context.stack << context.tag_id
                    break
                end

                case context.tag_id
                when :TO_DO
                else
                    raise "unhandled " + context.tag_id.to_s
                end
            end # while
        end # parse

        private :parse

        def to_tag
            "HWPTAG::CTRL_HEADER"
        end

        def debug
            puts "\t"*@level +"CtrlHeader:" + @ctrl_id
        end
    end # CtrlHeader

    # TODO REVERSE-ENGINEERING
    # 리스트 헤더: Table 다음에 올 경우 셀 속성
    class ListHeader
        attr_reader :level, :num_para,
                    # table cell
                    :col_addr, :row_addr, :col_span, :row_span,
                    :width, :height, :margins
        def initialize context
            @level = context.level
            s_io = StringIO.new context.data
            @num_para = s_io.read(2).unpack("v").pop
            bit = s_io.read(4).unpack("b32").pop
            # TODO 테이블 셀이 아닌 경우에 대한 처리가 필요하다. 또는 테이블 셀 감지
            s_io.pos = 8 # 셀 속성 시작 위치
            @col_addr,
            @row_addr,
            @col_span,
            @row_span,
            @width,
            @height,
            @margins = s_io.read.unpack("v4 V2 v4 v")
            #p data.bytesize
            # 4바이트가 남는다
            s_io.close
        end

        def to_tag
            "HWPTAG::LIST_HEADER"
        end

        def debug
            puts "\t"*@level +"ListHeader:"
        end
    end

    class CtrlData
        attr_accessor :level
        def initialize context
            @level = context.level
            STDERR.puts "{#self.class.name}: not implemented"
        end
    end

    # TODO REVERSE-ENGINEERING
    class Table
        attr_reader :level, :prop, :n_rows, :n_cols, :cell_spacing, :margins, :row_size, :border_fill_id
        def initialize context
            @level = context.level
            s_io = StringIO.new context.data
            @prop = s_io.read(4).unpack("V")
            @n_rows = s_io.read(2).unpack("v")[0]
            @n_cols = s_io.read(2).unpack("v")[0]
            @cell_spacing = s_io.read(2).unpack("v")
            @margins = s_io.read(2*4).unpack("v4")
            @row_size = s_io.read(2*n_rows).unpack("v*")
            @border_fill_id = s_io.read(2).unpack("v")
            #valid_zone_info_size = s_io.read(2).unpack("v")[0]
            #zone_prop = s_io.read(10*valid_zone_info_size).unpack("v*")
            s_io.close
        end

        def debug
            puts "\t"*@level +"Table:"
        end
    end

    class ShapeComponentLine
        attr_reader :level
        def initialize context
            @level = context.level
            STDERR.puts "{#self.class.name}: not implemented"
        end
    end

    class ShapeComponentRectangle
        attr_reader :level
        def initialize context
            @level = context.level
            STDERR.puts "{#self.class.name}: not implemented"
        end
    end

    class ShapeComponentEllipse
        attr_reader :level
        def initialize context
            @level = context.level
            STDERR.puts "{#self.class.name}: not implemented"
        end
    end

    class ShapeComponentArc
        attr_reader :level
        def initialize context
            @level = context.level
            STDERR.puts "{#self.class.name}: not implemented"
        end
    end

    class ShapeComponentPolygon
        attr_reader :level
        def initialize context
            @level = context.level
            STDERR.puts "{#self.class.name}: not implemented"
        end
    end

    class ShapeComponentCurve
        attr_reader :level
        def initialize context
            @level = context.level
            STDERR.puts "{#self.class.name}: not implemented"
        end
    end

    class ShapeComponentOLE
        attr_reader :level
        def initialize context
            @level = context.level
            STDERR.puts "{#self.class.name}: not implemented"
        end
    end

    # TODO REVERSE-ENGINEERING
    class ShapeComponentPicture
        attr_reader :level
        def initialize context
            @level = context.level
            data.unpack("V6sv4Vv vV vVvV")
        end
    end

    class ShapeComponentContainer
        attr_reader :level
        def initialize context
            @level = context.level
            STDERR.puts "{#self.class.name}: not implemented"
        end
    end

    class ShapeComponentTextArt
        attr_reader :level
        def initialize context
            @level = context.level
            STDERR.puts "{#self.class.name}: not implemented"
        end
    end

    class ShapeComponentUnknown
        attr_reader :level
        def initialize context
            @level = context.level
            STDERR.puts "{#self.class.name}: not implemented"
        end
    end

    class PageDef
        attr_reader :level, :width, :height, :left_margin, :right_margin,
                    :top_margin, :bottom_margin, :header_margin,
                    :footer_margin, :gutter_margin
        def initialize context
            @level = context.level

            @width,         @height,
            @left_margin,   @right_margin,
            @top_margin,    @bottom_margin,
            @header_margin, @footer_margin,
            @gutter_margin, @property = context.data.unpack("V*")
        end

        def to_tag
            "HWPTAG::PAGE_DEF"
        end

        def debug
            puts "\t"*@level +"PageDef:"# + @data.unpack("V*").to_s
        end
    end

    # TODO REVERSE-ENGINEERING
    class FootnoteShape
        attr_reader :level
        def initialize context
            @level = context.level
            @data = context.data
            s_io = StringIO.new context.data
            s_io.read(4)
            s_io.read(2)
            s_io.read(2).unpack("CC").pack("U*")
            s_io.read(2)
            s_io.read(2)
            s_io.read(2)
            s_io.read(2)
            s_io.read(2)
            s_io.read(2)
            s_io.read(1)
            s_io.read(1)
            s_io.read(4)
            # 바이트가 남는다
            s_io.close
        end

        def to_tag
            "HWPTAG::FOOTNOTE_SHAPE"
        end

        def debug
            puts "\t"*@level +"FootnoteShape:"# + @data.inspect
        end
    end

    class PageBorderFill
        attr_reader :level
        def initialize context
            @level = context.level
            # 스펙 문서 58쪽 크기 불일치 12 != 14
            #p data.unpack("ISSSSS") # 마지막 2바이트 S, 총 14바이트
        end

        def to_tag
            "HWPTAG::PAGE_BORDER_FILL"
        end

        def debug
            puts "\t"*@level +"PageBorderFill:"
        end
    end

    class Reserved
        attr_reader :level
        def initialize context
            @level = context.level
            STDERR.puts "{#self.class.name}: not implemented"
        end
    end

    class MemoShape
        attr_reader :level
        def initialize context
            @level = context.level
            STDERR.puts "{#self.class.name}: not implemented"
        end
    end

    class MemoList
        attr_reader :level
        def initialize context
            @level = context.level
            STDERR.puts "{#self.class.name}: not implemented"
        end
    end

    class ChartData
        attr_reader :level
        def initialize context
            @level = context.level
            STDERR.puts "{#self.class.name}: not implemented"
        end
    end
end # Record::Section
