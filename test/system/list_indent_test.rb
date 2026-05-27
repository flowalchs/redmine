# frozen_string_literal: true

require_relative '../application_system_test_case'

class ListIndentSystemTest < ApplicationSystemTestCase
  def setup
    super
    log_user('jsmith', 'jsmith')
  end

  # Tab: inserts 2 spaces for bullet lists, 4 spaces for ordered lists
  def test_tab_indents_common_mark_bullet_list
    with_settings :text_formatting => 'common_mark' do
      visit '/projects/ecookbook/issues/new'

      within('form#issue-form') do
        el = find('#issue_description')
        el.click
        set_textarea_value 'issue_description', "- item", selection: [0, text.length]
        el.send_keys(:tab)
        assert_equal "  - item", el.value
      end
    end
  end

  def test_tab_indents_common_mark_ordered_list
    with_settings :text_formatting => 'common_mark' do
      visit '/projects/ecookbook/issues/new'

      within('form#issue-form') do
        el = find('#issue_description')
        el.click
        set_textarea_value 'issue_description', "1. item", selection: [0, text.length]
        el.send_keys(:tab)
        assert_equal "    1. item", el.value
      end
    end
  end

  # Shift+Tab: removes indentation
  def test_shift_tab_unindents_common_mark_bullet_list
    with_settings :text_formatting => 'common_mark' do
      visit '/projects/ecookbook/issues/new'

      within('form#issue-form') do
        el = find('#issue_description')
        el.click
        set_textarea_value 'issue_description', "- parent\n  - child", selection: [0, text.length]
        el.send_keys([:shift, :tab])
        assert_equal "- parent\n- child", el.value
      end
    end
  end

  def test_shift_tab_removes_partial_indent_on_common_mark_list
    # Removes only as many spaces as exist when indent is less than the step size
    with_settings :text_formatting => 'common_mark' do
      visit '/projects/ecookbook/issues/new'

      within('form#issue-form') do
        el = find('#issue_description')
        el.click
        set_textarea_value 'issue_description', "- parent\n - child", selection: [0, text.length]
        el.send_keys([:shift, :tab])
        assert_equal "- parent\n- child", el.value
      end
    end
  end

  def test_shift_tab_does_nothing_on_common_mark_list_with_no_indent
    with_settings :text_formatting => 'common_mark' do
      visit '/projects/ecookbook/issues/new'

      within('form#issue-form') do
        el = find('#issue_description')
        el.click
        set_textarea_value 'issue_description', "- item", selection: [0, text.length]
        el.send_keys([:shift, :tab])
        assert_equal "- item", el.value
      end
    end
  end

  def test_tab_indents_multiple_lines_when_selected
    with_settings :text_formatting => 'common_mark' do
      visit '/projects/ecookbook/issues/new'

      within('form#issue-form') do
        el = find('#issue_description')
        el.click
        set_textarea_value 'issue_description', "- item1\n- item2", selection: [0, text.length]
        el.send_keys(:tab)
        assert_equal "  - item1\n  - item2", el.value
      end
    end
  end

  def test_tab_does_not_indent_without_list_or_selection
    with_settings :text_formatting => 'common_mark' do
      visit '/projects/ecookbook/issues/new'

      within('form#issue-form') do
        fill_in 'Description', with: "normal text"
        el = find('#issue_description')
        el.click
        el.send_keys(:tab)
        assert_equal "normal text", el.value
      end
    end
  end

  def test_tab_indents_only_selected_lines_block
    with_settings :text_formatting => 'common_mark' do
      visit '/projects/ecookbook/issues/new'

      within('form#issue-form') do
        text = "- item1\n- item2\n- item3"
        start = text.index("- item2")
        finish = start + "- item2".length
        el = find('#issue_description')
        el.click
        set_textarea_value 'issue_description', text, selection: [start, finish]
        el.send_keys(:tab)
        assert_equal "- item1\n  - item2\n- item3", el.value
      end
    end
  end

  def test_tab_indents_only_selected_lines_block_ordered_list
    with_settings :text_formatting => 'common_mark' do
      visit '/projects/ecookbook/issues/new'

      within('form#issue-form') do
        text = "1. item1\n1. item2\n1. item3"
        start = text.index("1. item2") + 5
        finish = start + 1
        el = find('#issue_description')
        el.click
        set_textarea_value 'issue_description', text, selection: [start, finish]
        el.send_keys(:tab)
        assert_equal "1. item1\n    1. item2\n1. item3", el.value
      end
    end
  end

  private

  # Sets textarea to support multi-line input and custom selection.
  # Avoids `fill_in`, which sends keystrokes and can trigger list autofill.
  def set_textarea_value(id, text, selection: nil)
    page.execute_script(
      "const el = document.getElementById(arguments[0]);" \
      "el.value = arguments[1];" \
      "if (arguments[2]) {" \
      "  el.setSelectionRange(arguments[2][0], arguments[2][1]);" \
      "} else {" \
      "  el.setSelectionRange(el.value.length, el.value.length);" \
      "}",
      id,
      text,
      selection
    )
  end
end
