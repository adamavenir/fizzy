module ApplicationHelper
  def page_title_tag
    account_name = if Current.account && Current.session&.identity&.users&.many?
      Current.account&.name
    end
    tag.title [ @page_title, account_name, "Fizzy" ].compact.join(" | ")
  end

  def render_markdown(text)
    return "" if text.blank?

    renderer = Redcarpet::Render::HTML.new(
      hard_wrap: true,
      link_attributes: { target: "_blank", rel: "noopener" }
    )
    markdown = Redcarpet::Markdown.new(renderer,
      autolink: true,
      tables: true,
      fenced_code_blocks: true,
      strikethrough: true,
      superscript: true,
      no_intra_emphasis: true
    )
    markdown.render(text).html_safe
  end

  def render_beads_markdown(text, board:)
    return "" if text.blank?

    # Pre-process to convert card references to markdown links
    processed = auto_link_card_references(text, board)

    # Render with Redcarpet
    html = render_markdown(processed)

    # Post-process to add preview data attributes
    add_preview_attributes(html, board)
  end

  private

  def auto_link_card_references(text, board)
    prefix = board&.beads_prefix
    return text unless prefix.present?

    # Replace card references with markdown links
    # Pattern matches #prefix-hash or #hash (but not if already in markdown link)
    text.gsub(/#([\w-]+)-([\w]+)\b|#([\w]+)\b/) do
      match_data = Regexp.last_match
      matched_text = match_data[0]

      # Skip if already inside a markdown link
      before_text = match_data.pre_match
      next matched_text if before_text =~ /\]\([^\)]*$/

      if match_data[1] && match_data[2]
        # Full ID: #prefix-hash
        matched_prefix = match_data[1]
        hash = match_data[2]

        target_board = Board.find_by(beads_prefix: matched_prefix)
        if target_board
          url = beads_short_link_path(matched_prefix, hash)
          "[##{hash}](#{url})"
        else
          matched_text
        end
      elsif match_data[3]
        # Short ID: #hash (use current board's prefix)
        hash = match_data[3]
        url = beads_short_link_path(prefix, hash)
        "[##{hash}](#{url})"
      else
        matched_text
      end
    end
  end

  def add_preview_attributes(html, board)
    prefix = board&.beads_prefix
    return html unless prefix.present?

    # Add data attributes to links that match /bd/ pattern
    html.gsub(%r{<a href="/bd/([\w-]+)/([\w]+)"([^>]*)>(.*?)</a>}) do
      matched_prefix = $1
      hash = $2
      existing_attrs = $3
      link_text = $4

      preview_url = beads_preview_path(matched_prefix, hash)
      %{<a href="/bd/#{matched_prefix}/#{hash}"#{existing_attrs} data-controller="card-link-preview" data-card-link-preview-url-value="#{preview_url}" data-action="mouseenter->card-link-preview#mouseEnter mouseleave->card-link-preview#mouseLeave">#{link_text}</a>}
    end.html_safe
  end

  def icon_tag(name, **options)
    tag.span class: class_names("icon icon--#{name}", options.delete(:class)), "aria-hidden": true, **options
  end

  def inline_svg(name)
    file_path = "#{Rails.root}/app/assets/images/#{name}.svg"
    return File.read(file_path).html_safe if File.exist?(file_path)
    "(not found)"
  end

  def back_link_to(label, url, action, **options)
    link_to url, class: "btn btn--back", data: { controller: "hotkey", action: action }, **options do
      icon_tag("arrow-left") + tag.strong("Back to #{label}", class: "overflow-ellipsis") + tag.kbd("ESC", class: "txt-x-small hide-on-touch").html_safe
    end
  end
end
