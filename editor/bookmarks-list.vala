/*
  This file is part of Dconf Editor

  Dconf Editor is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  Dconf Editor is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with Dconf Editor.  If not, see <https://www.gnu.org/licenses/>.
*/

using Gtk;

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/bookmarks-list.ui")]
private class BookmarksList : Overlay
{
    [GtkChild] private ScrolledWindow   scrolled;
    [GtkChild] private ListBox          bookmarks_list_box;
    [GtkChild] private Box              edit_mode_box;

    [GtkChild] private ModelButton enter_edit_mode_button;
    [GtkChild] private ModelButton leave_edit_mode_button;
    public string edit_mode_action_prefix
    {
        construct
        {
            // TODO sanitize "value"
            enter_edit_mode_button.set_detailed_action_name (value + ".set-edit-mode(true)");
            leave_edit_mode_button.set_detailed_action_name (value + ".set-edit-mode(false)");
        }
    }

    [GtkChild] private RegistryPlaceholder placeholder;
    public bool big_placeholder { internal construct { placeholder.big = value; }}

    private HashTable<string, Bookmark> bookmarks_hashtable = new HashTable<string, Bookmark> (str_hash, str_equal);
    private Bookmark? last_row = null;
    private uint n_bookmarks = 0;

    private string schema_id = "ca.desrt.dconf-editor.Bookmarks";   // TODO move in a library
    private GLib.Settings settings;
    ulong bookmarks_changed_handler = 0;

    public string schema_path
    {
        internal set
        {
            settings = new GLib.Settings.with_path (schema_id, value);

            bookmarks_changed_handler = settings.changed ["bookmarks"].connect (on_bookmarks_changed);
            ulong bookmarks_writable_handler = settings.writable_changed ["bookmarks"].connect (on_writability_changed);

            Variant bookmarks_variant = settings.get_value ("bookmarks");
            bool is_writable = settings.is_writable ("bookmarks");

            create_bookmark_rows (bookmarks_variant);
            edit_mode_box.set_visible (is_writable && !has_empty_list_class);

            bookmarks_changed (settings.get_value ("bookmarks"), settings.is_writable ("bookmarks"));

            destroy.connect (() => {
                    settings.disconnect (bookmarks_changed_handler);
                    settings.disconnect (bookmarks_writable_handler);
                });
        }
    }

    internal signal void bookmarks_changed (Variant bookmarks_variant, bool writable);
    private void on_bookmarks_changed (GLib.Settings _settings, string key)
    {
        Variant bookmarks_variant = _settings.get_value (key);
        create_bookmark_rows (bookmarks_variant);
        bookmarks_changed (bookmarks_variant, _settings.is_writable (key));
    }

    internal signal void writability_changed (bool writable);
    private void on_writability_changed (GLib.Settings _settings, string key)
    {
        bool is_writable = _settings.is_writable (key);
        writability_changed (is_writable);
        edit_mode_box.set_visible (is_writable);
    }

    internal signal void selection_changed ();

    internal enum SelectionState {
        EMPTY,
        UNIQUE,
        FIRST,
        LAST,
        MIDDLE,
        MULTIPLE
    }

    internal SelectionState get_selection_state ()
    {
        List<weak ListBoxRow> selected_rows = bookmarks_list_box.get_selected_rows ();
        uint n_selected_rows = selected_rows.length ();

        if (n_selected_rows == 0)
            return SelectionState.EMPTY;
        if (n_selected_rows >= 2)
            return SelectionState.MULTIPLE;

        int index = selected_rows.nth_data (0).get_index ();
        bool is_first = index == 0;
        bool is_last = bookmarks_list_box.get_row_at_index (index + 1) == null;
        if (is_first && is_last)
            return SelectionState.UNIQUE;
        if (is_first)
            return SelectionState.FIRST;
        if (is_last)
            return SelectionState.LAST;
        return SelectionState.MIDDLE;
    }

    internal void enter_edit_mode ()
    {
        bookmarks_list_box.grab_focus ();

        bookmarks_list_box.@foreach ((widget) => { ((Bookmark) widget).set_actionable (false); });
        bookmarks_list_box.set_activate_on_single_click (false);
        bookmarks_list_box.set_selection_mode (SelectionMode.MULTIPLE);
    }

    internal bool leave_edit_mode ()
    {

        ListBoxRow? row = (ListBoxRow?) bookmarks_list_box.get_focus_child ();  // broken, the child needs to have the global focus...
        bool give_focus_to_switch = row == null;
        if (give_focus_to_switch)
        {
            List<weak ListBoxRow> selected_rows = bookmarks_list_box.get_selected_rows ();
            row = selected_rows.nth_data (0);
        }

        bookmarks_list_box.@foreach ((widget) => { ((Bookmark) widget).set_actionable (true); });
        bookmarks_list_box.set_activate_on_single_click (true);
        bookmarks_list_box.set_selection_mode (SelectionMode.SINGLE);

        if (row != null)
            select_row_for_real ((!) row);

        return give_focus_to_switch;
    }

    internal Variant get_bookmarks_as_variant ()
    {
        return settings.get_value ("bookmarks");
    }

    internal string [] get_bookmarks_as_array ()
    {
        string [] all_bookmarks = settings.get_strv ("bookmarks");
        string [] unduplicated_bookmarks = {};
        foreach (string bookmark in all_bookmarks)
        {
            if (DConfWindow.is_path_invalid (bookmark))
                continue;
            if (bookmark in unduplicated_bookmarks)
                continue;
            unduplicated_bookmarks += bookmark;
        }
        return unduplicated_bookmarks;
    }

    private bool has_empty_list_class = false;
    internal bool create_bookmark_rows (Variant bookmarks_variant)
    {
        _create_bookmark_rows (bookmarks_variant, ref bookmarks_list_box, ref bookmarks_hashtable, ref last_row, ref n_bookmarks);
        bool no_bookmarks = n_bookmarks == 0;

        if (no_bookmarks && !has_empty_list_class)
        {
            bookmarks_list_box.get_style_context ().add_class ("empty-list");
            has_empty_list_class = true;
            edit_mode_box.hide ();
        }
        else if (!no_bookmarks && has_empty_list_class)
        {
            bookmarks_list_box.get_style_context ().remove_class ("empty-list");
            has_empty_list_class = false;
            edit_mode_box.show ();
        }

        return no_bookmarks;
    }
    private static void _create_bookmark_rows (Variant bookmarks_variant, ref ListBox bookmarks_list_box, ref HashTable<string, Bookmark> bookmarks_hashtable, ref Bookmark? last_row, ref uint n_bookmarks)
    {
        string saved_bookmark_name = "";
        ListBoxRow? selected_row = bookmarks_list_box.get_selected_row ();
        if (selected_row != null && ((!) selected_row) is Bookmark)
            saved_bookmark_name = ((Bookmark) (!) selected_row).bookmark_name;
        selected_row = null;

        bookmarks_list_box.@foreach ((widget) => widget.destroy ());
        bookmarks_hashtable.remove_all ();
        last_row = null;
        n_bookmarks = 0;

        string [] bookmarks = bookmarks_variant.get_strv ();
        string [] unduplicated_bookmarks = new string [0];
        foreach (string bookmark in bookmarks)
        {
            if (DConfWindow.is_path_invalid (bookmark))
                continue;
            if (bookmark in unduplicated_bookmarks)
                continue;
            unduplicated_bookmarks += bookmark;

            Bookmark bookmark_row = new Bookmark (bookmark);
            bookmarks_list_box.add (bookmark_row);
            bookmark_row.show ();
            bookmarks_hashtable.insert (bookmark, bookmark_row);
            last_row = bookmark_row;

            if (saved_bookmark_name == bookmark)
                selected_row = bookmark_row;
            n_bookmarks ++;
        }

        if (selected_row == null)
            selected_row = bookmarks_list_box.get_row_at_index (0);
        if (selected_row != null)
            bookmarks_list_box.select_row ((!) selected_row);
    }

    internal void update_bookmark_icon (string bookmark, BookmarkIcon icon)
    {
        Bookmark? bookmark_row = bookmarks_hashtable.lookup (bookmark);
        if (bookmark_row == null)
            return;
        Widget? bookmark_grid = ((!) bookmark_row).get_child ();
        if (bookmark_grid == null)
            assert_not_reached ();
        _update_bookmark_icon (((!) bookmark_grid).get_style_context (), icon);
    }
    private static inline void _update_bookmark_icon (StyleContext context, BookmarkIcon icon)
    {
        switch (icon)
        {
            case BookmarkIcon.VALID_FOLDER: context.add_class ("folder");
                return;
            case BookmarkIcon.EMPTY_FOLDER: context.add_class ("folder");
                                            context.add_class ("erase");
                return;
            case BookmarkIcon.SEARCH:       context.add_class ("search");
                return;
            case BookmarkIcon.EMPTY_OBJECT: context.add_class ("key");
                                            context.add_class ("dconf-key");
                                            context.add_class ("erase");
                return;
            case BookmarkIcon.DCONF_OBJECT: context.add_class ("key");
                                            context.add_class ("dconf-key");
                return;
            case BookmarkIcon.KEY_DEFAULTS: context.add_class ("key");
                                            context.add_class ("gsettings-key");
                return;
            case BookmarkIcon.EDITED_VALUE: context.add_class ("key");
                                            context.add_class ("gsettings-key");
                                            context.add_class ("edited");
                return;
            default: assert_not_reached ();
        }
    }

    /*\
    * * keyboard
    \*/

    internal void down_pressed ()
    {
        ListBoxRow? row = bookmarks_list_box.get_selected_row ();
        if (row == null)
            row = bookmarks_list_box.get_row_at_index (0);
        else
            row = bookmarks_list_box.get_row_at_index (((!) row).get_index () + 1);

        if (row == null)
            return;
        bookmarks_list_box.select_row ((!) row);
        ((!) row).grab_focus ();
    }

    internal void up_pressed ()
    {
        ListBoxRow? row = bookmarks_list_box.get_selected_row ();
        if (row == null)
            row = last_row;
        else
        {
            int index = ((!) row).get_index ();
            if (index <= 0)
                return;
            row = bookmarks_list_box.get_row_at_index (index - 1);
        }

        if (row == null)
            return;
        bookmarks_list_box.select_row ((!) row);
        ((!) row).grab_focus ();
    }

    internal void select_all ()
    {
        bookmarks_list_box.select_all ();
    }

    internal void unselect_all ()
    {
        bookmarks_list_box.unselect_all ();
    }

    /*\
    * * remote action entries
    \*/

    internal signal void update_bookmarks_icons (Variant bookmarks_variant);
    internal void trash_bookmark ()
    {
        ListBoxRow? row = (ListBoxRow?) bookmarks_list_box.get_focus_child ();
        bool focused_row_will_survive = row != null && !((!) row).is_selected ();

        string [] bookmarks_to_remove = new string [0];
        int upper_index = int.MAX;
        bookmarks_list_box.selected_foreach ((_list_box, selected_row) => {
                if (!(selected_row is Bookmark))
                    assert_not_reached ();
                bookmarks_to_remove += ((Bookmark) selected_row).bookmark_name;

                if (focused_row_will_survive)
                    return;

                int index = selected_row.get_index ();
                if (upper_index > index)
                    upper_index = index;
            });
        if (upper_index == int.MAX)
            assert_not_reached ();

        if (!focused_row_will_survive)
        {
            row = bookmarks_list_box.get_row_at_index (upper_index + 1);
            if (row == null)
            {
                if (upper_index > 0)
                    row = bookmarks_list_box.get_row_at_index (upper_index - 1);
                // TODO else quit mode
            }
        }
        if (row != null)
            bookmarks_list_box.select_row ((!) row);

        remove_bookmarks (settings, bookmarks_to_remove);
        update_bookmarks_icons (settings.get_value ("bookmarks"));
    }

    internal void move_top ()
    {
//        bookmarks_list_box.selected_foreach ((_list_box, selected_row) => {

        ListBoxRow? row = bookmarks_list_box.get_selected_row ();
        if (row == null)
            return; // TODO assert_not_reached?

        int index = ((!) row).get_index ();
        if (index < 0)
            assert_not_reached ();

        if (index == 0)
            return;
        bookmarks_list_box.remove ((!) row);
        bookmarks_list_box.prepend ((!) row);
        select_row_for_real ((!) row);

        Adjustment adjustment = bookmarks_list_box.get_adjustment ();
        adjustment.set_value (adjustment.get_lower ());

        update_bookmarks_after_move ();
    }

    internal void move_up ()
    {
        ListBoxRow? row = bookmarks_list_box.get_selected_row ();
        if (row == null)
            return; // TODO assert_not_reached?

        int index = ((!) row).get_index ();
        if (index < 0)
            assert_not_reached ();

        if (index == 0)
            return;

        ListBoxRow? prev_row = bookmarks_list_box.get_row_at_index (index - 1);
        if (prev_row == null)
            assert_not_reached ();

        Allocation list_allocation, row_allocation;
        scrolled.get_allocation (out list_allocation);
        Widget? row_child = ((!) prev_row).get_child ();    // using prev_row as the allocation is not updated anyway
        if (row_child == null)
            assert_not_reached ();
        ((!) row_child).get_allocation (out row_allocation);
        Adjustment adjustment = bookmarks_list_box.get_adjustment ();
        int proposed_adjustemnt_value = row_allocation.y + (int) ((row_allocation.height - list_allocation.height) / 3.0);
        bool should_adjust = adjustment.get_value () > proposed_adjustemnt_value;

        bookmarks_list_box.unselect_row ((!) row);
        bookmarks_list_box.remove ((!) prev_row);

        if (should_adjust)
            adjustment.set_value (proposed_adjustemnt_value);

        bookmarks_list_box.insert ((!) prev_row, index);
        bookmarks_list_box.select_row ((!) row);

        update_bookmarks_after_move ();
    }

    internal void move_down ()
    {
        ListBoxRow? row = bookmarks_list_box.get_selected_row ();
        if (row == null)
            return; // TODO assert_not_reached?

        int index = ((!) row).get_index ();
        if (index < 0)
            assert_not_reached ();

        ListBoxRow? next_row = bookmarks_list_box.get_row_at_index (index + 1);
        if (next_row == null)
            return;

        Allocation list_allocation, row_allocation;
        scrolled.get_allocation (out list_allocation);
        Widget? row_child = ((!) next_row).get_child ();    // using next_row as the allocation is not updated
        if (row_child == null)
            assert_not_reached ();
        ((!) row_child).get_allocation (out row_allocation);
        Adjustment adjustment = bookmarks_list_box.get_adjustment ();
        int proposed_adjustemnt_value = row_allocation.y + (int) (2 * (row_allocation.height - list_allocation.height) / 3.0);
        bool should_adjust = adjustment.get_value () < proposed_adjustemnt_value;

        bookmarks_list_box.unselect_row ((!) row);
        bookmarks_list_box.remove ((!) next_row);

        if (should_adjust)
            adjustment.set_value (proposed_adjustemnt_value);

        bookmarks_list_box.insert ((!) next_row, index);
        bookmarks_list_box.select_row ((!) row);

        update_bookmarks_after_move ();
    }

    internal void move_bottom ()
    {
//        bookmarks_list_box.selected_foreach ((_list_box, selected_row) => {

        ListBoxRow? row = bookmarks_list_box.get_selected_row ();
        if (row == null)
            return; // TODO assert_not_reached?

        int index = ((!) row).get_index ();
        if (index < 0)
            assert_not_reached ();

        bookmarks_list_box.remove ((!) row);
        bookmarks_list_box.insert ((!) row, -1);
        select_row_for_real ((!) row);

        Adjustment adjustment = bookmarks_list_box.get_adjustment ();
        adjustment.set_value (adjustment.get_upper ());

        update_bookmarks_after_move ();
    }

    private void select_row_for_real (ListBoxRow row)   // ahem...
    {
        bookmarks_list_box.unselect_row (row);
        bookmarks_list_box.select_row (row);
    }

    /*\
    * * callbacks
    \*/

    [GtkCallback]
    private void on_selection_changed ()
    {
        selection_changed ();
    }

    [GtkCallback]
    private void on_content_changed ()
    {
        List<weak Widget> widgets = bookmarks_list_box.get_children ();
        if (widgets.length () == 0)
            edit_mode_box.hide ();
        else
            edit_mode_box.show ();
    }
    /*\
    * * Bookmarks management
    \*/

    private void update_bookmarks_after_move ()
    {
        string [] new_bookmarks = get_bookmarks_list (ref bookmarks_list_box);

        string [] old_bookmarks = settings.get_strv ("bookmarks");  // be cool :-)
        foreach (string bookmark in old_bookmarks)
            if (!(bookmark in new_bookmarks))
                new_bookmarks += bookmark;

        SignalHandler.block (settings, bookmarks_changed_handler);
        settings.set_strv ("bookmarks", new_bookmarks);
        GLib.Settings.sync ();   // TODO better? really needed?
        SignalHandler.unblock (settings, bookmarks_changed_handler);
    }
    private static string [] get_bookmarks_list (ref ListBox bookmarks_list_box)
    {
        string [] bookmarks = new string [0];
        bookmarks_list_box.@foreach ((widget) => { bookmarks += ((Bookmark) widget).bookmark_name; });
        return bookmarks;
    }

    internal void append_bookmark (string bookmark, ViewType type)
    {
        _append_bookmark (settings, get_bookmark_name (bookmark, type));
    }
    private static void _append_bookmark (GLib.Settings settings, string bookmark_name)
    {
        string [] bookmarks = settings.get_strv ("bookmarks");
        if (bookmark_name in bookmarks)
            return;

        bookmarks += bookmark_name;
        settings.set_strv ("bookmarks", bookmarks);
    }

    internal void remove_bookmark (string bookmark, ViewType type)
    {
        _remove_bookmark (settings, get_bookmark_name (bookmark, type));
    }
    private static void _remove_bookmark (GLib.Settings settings, string bookmark_name)
    {
        string [] old_bookmarks = settings.get_strv ("bookmarks");
        if (!(bookmark_name in old_bookmarks))
            return;

        string [] new_bookmarks = new string [0];
        foreach (string bookmark in old_bookmarks)
            if (bookmark != bookmark_name && !(bookmark in new_bookmarks))
                new_bookmarks += bookmark;
        settings.set_strv ("bookmarks", new_bookmarks);
    }

    private static void remove_bookmarks (GLib.Settings settings, string [] bookmarks_to_remove)
    {
        string [] old_bookmarks = settings.get_strv ("bookmarks");

        string [] new_bookmarks = new string [0];
        foreach (string bookmark in old_bookmarks)
            if (!(bookmark in bookmarks_to_remove) && !(bookmark in new_bookmarks))
                new_bookmarks += bookmark;
        settings.set_strv ("bookmarks", new_bookmarks);
    }

    internal static inline string get_bookmark_name (string path, ViewType type)
    {
        if (type == ViewType.SEARCH)
            return "?" + path;
        else
            return path;
    }
}

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/bookmark.ui")]
private class Bookmark : ListBoxRow
{
    [GtkChild] private Label bookmark_label;

    public string bookmark_name { internal get; internal construct; }

    construct
    {
        string bookmark_text;
        ViewType bookmark_type;
        parse_bookmark_name (bookmark_name, out bookmark_text, out bookmark_type);

        construct_actions_names (bookmark_text, bookmark_type, out detailed_action_name, out inactive_action_name);
        set_actionable (true);

        bookmark_label.set_label (bookmark_text);
    }

    internal Bookmark (string bookmark_name)
    {
        Object (bookmark_name: bookmark_name);
    }

    internal void set_actionable (bool actionable)
    {
        if (actionable)
            set_detailed_action_name (detailed_action_name);
        else
            set_detailed_action_name (inactive_action_name);
    }

    /*\
    * * Actions names
    \*/

    private string detailed_action_name;
    private string inactive_action_name;

    private static void construct_actions_names (string     bookmark_text,
                                                 ViewType   bookmark_type,
                                             out string     detailed_action_name,
                                             out string     inactive_action_name)
    {
        switch (bookmark_type)
        {
            case ViewType.SEARCH:
                Variant variant = new Variant.string (bookmark_text);
                detailed_action_name = "ui.open-search(" + variant.print (false) + ")";
                inactive_action_name = "ui.empty('')";
                return;

            case ViewType.FOLDER:
                Variant variant = new Variant.string (bookmark_text);
                detailed_action_name = "ui.open-folder(" + variant.print (false) + ")";
                inactive_action_name = "ui.empty('')";
                return;

            case ViewType.OBJECT:
                Variant variant = new Variant ("(sq)", bookmark_text, ModelUtils.undefined_context_id);  // TODO save context
                detailed_action_name = "ui.open-object(" + variant.print (true) + ")";
                inactive_action_name = "ui.empty(('',uint16 65535))";
                return;

            case ViewType.CONFIG:
            default: assert_not_reached ();
        }
    }

    private static void parse_bookmark_name (string     bookmark_name,
                                         out string     bookmark_text,
                                         out ViewType   bookmark_type)
    {
        if (bookmark_name.has_prefix ("?"))
        {
            bookmark_text = bookmark_name.slice (1, bookmark_name.length);
            bookmark_type = ViewType.SEARCH;
        }
        else if (ModelUtils.is_folder_path (bookmark_name))
        {
            bookmark_text = bookmark_name;
            bookmark_type = ViewType.FOLDER;
        }
        else
        {
            bookmark_text = bookmark_name;
            bookmark_type = ViewType.OBJECT;
        }
    }
}
