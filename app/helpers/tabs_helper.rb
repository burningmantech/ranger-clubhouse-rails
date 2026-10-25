# frozen_string_literal: true

# DaisyUI Tab Navigation Helper
# See: https://daisyui.com/components/tab/
#
module TabsHelper
  include ActionView::Helpers::CaptureHelper

  def tab_navigation(id, active_tab = nil, options = {}, &block)
    tabs = TabsComponent.new(self, id, active_tab, options)
    # Ignore any content that is not rendered within a pane, yet building up the panes.
    capture(tabs, &block)
    tabs.build
  end

  class TabsComponent
    include ActionView::Helpers::TagHelper
    include ActionView::Context

    attr_reader :panels, :active_tab, :tabs_id

    # daisyUI tab classes. An idle tab carries no class of its own.
    TABS_LIST = "tabs tabs-border"
    TAB_BASE = "tab"
    TAB_ACTIVE = "tab-active"

    def initialize(view_context, tabs_id, active_tab, options = {})
      @view_context = view_context
      @tabs_id = tabs_id
      @active_tab = active_tab
      @remote = options[:remote]
      @panes = []
    end

    def build
      controller_data = {
        controller: "tabs",
        tabs_toggle: "##{@tabs_id}",
        tabs_active_classes_value: TAB_ACTIVE
      }

      content_tag(:div, data: controller_data) do
        safe_join([build_tab_list, build_panels_container])
      end
    end

    def pane(title, target_id, options = {}, &block)
      @panes << {
        title:,
        target_id:,
        tab_id: "#{target_id}-tab",
        is_active: active_pane?(target_id),
        href: options[:href],
        content: block_given? ? @view_context.capture(&block) : nil
      }
      nil
    end

    def initial_content(target_id, &block)
      target = @panes.find { |pane| pane[:target_id] == target_id }
      target[:content] = @view_context.capture(&block) if target
    end

    private

    def active_pane?(target_id)
      @active_tab.present? ? @active_tab == target_id : @panes.empty?
    end

    def build_tab_list
      list_attrs = {
        class: TABS_LIST,
        role: "tablist",
        "aria-label": "Tabs"
      }

      content_tag(:div, list_attrs) do
        safe_join(@panes.map { |panel| build_tab_item(panel) })
      end
    end

    def build_panels_container
      safe_join(@panes.map { |panel| build_panel(panel) })
    end

    def build_tab_item(panel)
      if panel[:href]
        # Remote tab - use anchor for Turbo compatibility
        content_tag(:a, panel[:title], tab_link_options(panel))
      else
        # Static tab - use button per DaisyUI convention
        content_tag(:button, panel[:title], tab_button_options(panel))
      end
    end

    def tab_base_options(panel)
      {
        id: panel[:tab_id],
        class: tab_classes(panel[:is_active]),
        role: "tab",
        "aria-controls": panel[:target_id],
        "aria-selected": panel[:is_active].to_s,
        tabindex: panel[:is_active] ? "0" : "-1",
        data: {
          action: "click->tabs#show",
          tabs_target: "##{panel[:target_id]}"
        }
      }
    end

    def tab_button_options(panel)
      tab_base_options(panel).merge(type: "button")
    end

    def tab_link_options(panel)
      options = tab_base_options(panel)
      options[:href] = panel[:href]
      options["data-remote-tab"] = true
      options
    end

    def build_panel(panel)
      tag_type = panel[:href] ? "turbo-frame" : :div
      content_tag(tag_type, panel[:content], panel_attributes(panel))
    end

    def panel_attributes(panel)
      {
        id: panel[:target_id],
        class: panel_classes(panel[:is_active]),
        role: "tabpanel",
        "aria-labelledby": panel[:tab_id],
        tabindex: "0"
      }
    end

    def tab_classes(is_active)
      class_names(TAB_BASE, TAB_ACTIVE => is_active)
    end

    def panel_classes(is_active)
      class_names("mt-4", hidden: !is_active)
    end
  end
end
