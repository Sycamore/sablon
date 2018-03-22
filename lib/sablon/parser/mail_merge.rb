module Sablon
  module Parser
    class MailMerge
      class MergeField
        KEY_PATTERN = /^\s*MERGEFIELD\s+([^ ]+)\s+\\\*\s+MERGEFORMAT\s*$/

        def valid?
          expression
        end

        def expression
          $1 if @raw_expression =~ KEY_PATTERN
        end

        private

        def replace_field_display(node, content, env)
          paragraph = node.ancestors(".//w:p").first
          display_node = get_display_node(node)
          content.append_to(paragraph, display_node, env)
          display_node.remove
        end

        def get_display_node(node)
          node.search(".//w:t").first
        end
      end

      class ComplexField < MergeField
        def initialize(nodes)
          @nodes = nodes
          @raw_expression = @nodes.flat_map {|n| n.search(".//w:instrText").map(&:content) }.join
        end

        def valid?
          separate_node && get_display_node(pattern_node) && expression
        end

        def replace(content, env)
          replace_field_display(pattern_node, content, env)
          (@nodes - [pattern_node]).each(&:remove)
        end

        def remove
          @nodes.each(&:remove)
        end

        def ancestors(*args)
          @nodes.first.ancestors(*args)
        end

        def start_node
          @nodes.first
        end

        def end_node
          @nodes.last
        end

        private
        def pattern_node
          separate_node.next_element
        end

        def separate_node
          @nodes.detect {|n| !n.search(".//w:fldChar[@w:fldCharType='separate']").empty? }
        end
      end

      class SimpleField < MergeField
        def initialize(node)
          @node = node
          @raw_expression = @node["w:instr"]
        end

        def replace(content, env)
          remove_extra_runs!
          if content.is_a?(Sablon::Content::WordML)
            template_paragraph = @node.ancestors(".//w:p").first
            if env.remove_fields_only
              template_paragraph.remove if template_paragraph.present?
            else
              if env.keep_merge_fields && template_paragraph.present?
                template_paragraph.add_previous_sibling(template_paragraph.dup)
              end
              if env.inherit_styles && template_paragraph.present?
                inherit_template_styles(content, template_paragraph)
              end
            end
          end
          replace_field_display(@node, content, env) unless env.remove_fields_only
          @node.replace(@node.children) unless env.keep_merge_fields
        end

        def inherit_template_styles(content, template_paragraph)
          doc_fragment = content.xml
          template_props = template_paragraph && template_paragraph.element_children.select { |child| child.name == "pPr" }.first
          if template_props.present?
            paragraph_children = doc_fragment.element_children.select { |child| child.name == "w:p" }
            paragraph_children.each do |paragraph|
              props_node = paragraph.element_children.select { |child| child.name == "w:pPr" }.first
              props_node.remove if props_node.present?
              paragraph.children.first.add_previous_sibling(template_props.dup)
            end
          end
        end

        def remove
          @node.remove
        end

        def ancestors(*args)
          @node.ancestors(*args)
        end

        def start_node
          @node
        end
        alias_method :end_node, :start_node

        private
        def remove_extra_runs!
          @node.search(".//w:r")[1..-1].each(&:remove)
        end
      end

      def parse_fields(xml)
        fields = []
        xml.traverse do |node|
          if node.name == "fldSimple"
            field = SimpleField.new(node)
          elsif node.name == "fldChar" && node["w:fldCharType"] == "begin"
            field = build_complex_field(node)
          end
          fields << field if field && field.valid?
        end
        fields
      end

      private

      def build_complex_field(node)
        possible_field_node = node.parent
        field_nodes = [possible_field_node]
        while possible_field_node && possible_field_node.search(".//w:fldChar[@w:fldCharType='end']").empty?
          possible_field_node = possible_field_node.next_element
          field_nodes << possible_field_node
        end
        # skip instantiation if no end tag
        ComplexField.new(field_nodes) if field_nodes.last
      end
    end
  end
end
