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

private class DConfHeaderBar : BrowserHeaderBar
{
    private Bookmarks bookmarks_button;

    private bool _delay_mode = false;
    [CCode (notify = false)] internal bool delay_mode
    {
        private  get { return _delay_mode; }
        internal set
        {
            if (_delay_mode == value)
                return;
            _delay_mode = value;
            update_modifications_button ();
            update_hamburger_menu ();
        }
    }

    construct
    {
        install_action_entries ();

        add_bookmarks_revealer ();
        add_bookmarks_controller ();
        add_show_modifications_button ();
        add_modifications_actions_button ();
        construct_modifications_actions_button_menu ();

        register_bookmarks_modes ();
        register_modifications_mode ();
    }

    internal DConfHeaderBar (NightLightMonitor _night_light_monitor)
    {
        Object (night_light_monitor: _night_light_monitor, about_action_label: _("About Dconf Editor"));
    }

    protected override void set_window_size (AdaptativeWidget.WindowSize new_size)
    {
        bool _disable_popovers = disable_popovers;

        base.set_window_size (new_size);

        if (disable_popovers != _disable_popovers)
            update_bookmarks_button_visibility ();
        update_modifications_button ();
    }

    private void update_bookmarks_button_visibility ()
    {
        if (disable_popovers || modifications_mode_on)
        {
            bookmarks_button.active = false;

            bookmarks_button.sensitive = false;
            bookmarks_revealer.set_reveal_child (false);
        }
        else
        {
            bookmarks_button.sensitive = true;
            bookmarks_revealer.set_reveal_child (true);
        }
    }

    /*\
    * * bookmarks revealer
    \*/

    internal signal void update_bookmarks_icons (Variant bookmarks_variant);

    private Revealer bookmarks_revealer;

    private void add_bookmarks_revealer ()
    {
        bookmarks_revealer = new Revealer ();
        bookmarks_revealer.transition_type = RevealerTransitionType.SLIDE_LEFT;
        bookmarks_revealer.reveal_child = true;
        bookmarks_revealer.get_style_context ().add_class ("headerbar-revealer");

        bookmarks_button = new Bookmarks ("/ca/desrt/dconf-editor/");
        bookmarks_button.valign = Align.CENTER;
        bookmarks_button.focus_on_click = false;
        bookmarks_button.update_bookmarks_icons.connect (update_bookmarks_icons_cb);
        bookmarks_button.get_style_context ().add_class ("image-button");   // TODO check https://bugzilla.gnome.org/show_bug.cgi?id=756731

        bookmarks_button.visible = true;
        bookmarks_revealer.add (bookmarks_button);
        bookmarks_revealer.visible = true;
        center_box.pack_end (bookmarks_revealer);
    }

    private void update_bookmarks_icons_cb (Variant bookmarks_variant)
    {
        update_bookmarks_icons (bookmarks_variant);
    }

    /*\
    * * bookmarks stack
    \*/

    private BookmarksController bookmarks_controller;

    private void add_bookmarks_controller ()
    {
        bookmarks_controller = new BookmarksController ("bmk", false);
        bookmarks_controller.hexpand = true;

        bookmarks_controller.visible = false;
        pack_start (bookmarks_controller);
    }

    /*\
    * * use-bookmarks mode
    \*/

    private uint8 use_bookmarks_mode_id = 0;
    private bool use_bookmarks_mode_on = false;

    internal void show_use_bookmarks_view ()
        requires (use_bookmarks_mode_id > 0)
    {
        change_mode (use_bookmarks_mode_id);
    }

    private void register_bookmarks_modes ()
    {
        use_bookmarks_mode_id = register_new_mode ();
        edit_bookmarks_mode_id = register_new_mode ();

        this.change_mode.connect (mode_changed_bookmarks);
    }

    private void mode_changed_bookmarks (uint8 requested_mode_id)
    {
        mode_changed_use_bookmarks (requested_mode_id);
        mode_changed_edit_bookmarks (requested_mode_id);
    }

    private void mode_changed_use_bookmarks (uint8 requested_mode_id)
        requires (use_bookmarks_mode_id > 0)
    {
        if (is_not_requested_mode (use_bookmarks_mode_id, requested_mode_id, ref use_bookmarks_mode_on))
            return;

        set_default_widgets_states (/* show go_back_button      */ true,
                                    /* show ltr_left_separator  */ false,
                                    /* title_label text or null */ _("Bookmarks"),
                                    /* show info_button         */ false,
                                    /* show ltr_right_separator */ false,
                                    /* show quit_button_stack   */ true);
    }

    /*\
    * * edit-bookmarks mode
    \*/

    private uint8 edit_bookmarks_mode_id = 0;
    private bool edit_bookmarks_mode_on = false;

    internal void show_edit_bookmarks_view ()
        requires (edit_bookmarks_mode_id > 0)
    {
        change_mode (edit_bookmarks_mode_id);
    }

    private void mode_changed_edit_bookmarks (uint8 requested_mode_id)
        requires (edit_bookmarks_mode_id > 0)
    {
        if (is_not_requested_mode (edit_bookmarks_mode_id, requested_mode_id, ref edit_bookmarks_mode_on))
        {
            bookmarks_controller.hide ();
            return;
        }

        set_default_widgets_states (/* show go_back_button      */ true,
                                    /* show ltr_left_separator  */ true,
                                    /* title_label text or null */ null,
                                    /* show info_button         */ false,
                                    /* show ltr_right_separator */ false,
                                    /* show quit_button_stack   */ true);
        bookmarks_controller.show ();
    }

    /*\
    * * show-modifications button
    \*/

    private Button show_modifications_button;

    private void add_show_modifications_button ()
    {
        show_modifications_button = new Button.from_icon_name ("document-open-recent-symbolic");
        show_modifications_button.valign = Align.CENTER;
        show_modifications_button.action_name = "ui.show-in-window-modifications";
        show_modifications_button.get_style_context ().add_class ("titlebutton");

        show_modifications_button.visible = true;
        quit_button_stack.add (show_modifications_button);
    }

    /*\
    * *
    \*/

    private MenuButton modifications_actions_button;

    private void add_modifications_actions_button ()
    {
        modifications_actions_button = new MenuButton ();
        Image view_more_image = new Image.from_icon_name ("view-more-symbolic", IconSize.BUTTON);
        modifications_actions_button.set_image (view_more_image);
        modifications_actions_button.valign = Align.CENTER;
        modifications_actions_button.get_style_context ().add_class ("image-button");

        modifications_actions_button.visible = false;
        pack_end (modifications_actions_button);
    }

    /*\
    * *
    \*/

    internal string [] get_bookmarks ()     { return bookmarks_button.get_bookmarks (); }

    internal void update_bookmark_icon (string bookmark, BookmarkIcon icon) { bookmarks_button.update_bookmark_icon (bookmark, icon); }

    /*\
    * * should move back
    \*/

    internal override void set_path (ViewType type, string path)
    {
        current_type = type;
        current_path = path;

        path_widget.set_path (type, path);
        bookmarks_button.set_path (type, path);

        update_hamburger_menu ();
    }

    internal override bool has_popover ()
    {
        if (base.has_popover ())
            return true;
        if (bookmarks_button.active)
            return true;
        return false;
    }



    internal override bool next_match ()
    {
        if (bookmarks_button.active)
            return bookmarks_button.next_match ();
        return false;
    }

    internal override bool previous_match ()
    {
        if (bookmarks_button.active)
            return bookmarks_button.previous_match ();
        return false;
    }

    internal override void close_popovers ()
    {
        hide_hamburger_menu ();
        if (bookmarks_button.active)
            bookmarks_button.active = false;
        path_widget.close_popovers ();
    }

    internal void click_bookmarks_button ()
    {
        hide_hamburger_menu ();
        if (bookmarks_button.sensitive)
            bookmarks_button.clicked ();
    }

    internal void bookmark_current_path ()
    {
        hide_hamburger_menu ();
        bookmarks_button.bookmark_current_path ();
        update_hamburger_menu ();
    }

    internal void unbookmark_current_path ()
    {
        hide_hamburger_menu ();
        bookmarks_button.unbookmark_current_path ();
        update_hamburger_menu ();
    }

    /*\
    * * hamburger menu
    \*/

    internal override void toggle_hamburger_menu ()
    {
        if (modifications_actions_button.visible)
            modifications_actions_button.active = !modifications_actions_button.active;
        else
            base.toggle_hamburger_menu ();
    }

    protected override void populate_menu (ref GLib.Menu menu)
    {
        bool bookmarks_mode_on = use_bookmarks_mode_on || edit_bookmarks_mode_on;

        if (disable_popovers)
            append_bookmark_section (current_type, current_path, BookmarksList.get_bookmark_name (current_path, current_type) in get_bookmarks (), bookmarks_mode_on, ref menu);

        if (!bookmarks_mode_on)
            append_or_not_delay_mode_section (delay_mode, current_type == ViewType.FOLDER, current_path, ref menu);
    }

    private static void append_bookmark_section (ViewType current_type, string current_path, bool is_in_bookmarks, bool bookmarks_mode_on, ref GLib.Menu menu)
    {
        GLib.Menu section = new GLib.Menu ();

        if (bookmarks_mode_on)
            section.append (_("Hide bookmarks"), "ui.empty");    // button hidden in current design
        else
        {
            if (is_in_bookmarks)
                section.append (_("Unbookmark"), "headerbar.unbookmark-current");
            else
                section.append (_("Bookmark"), "headerbar.bookmark-current");

            section.append (_("Show bookmarks"), "ui.show-in-window-bookmarks");
        }
        section.freeze ();
        menu.append_section (null, section);
    }

    private static void append_or_not_delay_mode_section (bool delay_mode, bool is_folder_view, string current_path, ref GLib.Menu menu)
    {
        if (delay_mode && !is_folder_view)
            return;

        GLib.Menu section = new GLib.Menu ();
        if (!delay_mode)
            section.append (_("Enter delay mode"), "ui.enter-delay-mode");
        if (is_folder_view)
        {
            Variant variant = new Variant.string (current_path);
            section.append (_("Reset visible keys"), "ui.reset-visible(" + variant.print (false) + ")");
            section.append (_("Reset view recursively"), "ui.reset-recursive(" + variant.print (false) + ")");
        }
        section.freeze ();
        menu.append_section (null, section);
    }
    /*\
    * * in-window modifications
    \*/

    private uint8 modifications_mode_id = 0;
    private bool modifications_mode_on = false;

    internal void show_modifications_view ()
        requires (modifications_mode_id > 0)
    {
        change_mode (modifications_mode_id);
    }

    private void register_modifications_mode ()
    {
        modifications_mode_id = register_new_mode ();

        this.change_mode.connect (mode_changed_modifications);
    }

    private void mode_changed_modifications (uint8 requested_mode_id)
    {
        if (is_not_requested_mode (modifications_mode_id, requested_mode_id, ref modifications_mode_on))
        {
            modifications_actions_button.hide ();
            bookmarks_revealer.show ();
            update_bookmarks_button_visibility ();
            // if (path_widget.search_mode_enabled)
            //    path_widget.entry_grab_focus_without_selecting ();
            return;
        }

        set_default_widgets_states (/* show go_back_button      */ true,
                                    /* show ltr_left_separator  */ false,
                                    /* title_label text or null */ _("Pending"),
                                    /* show info_button         */ false,
                                    /* show ltr_right_separator */ false,
                                    /* show quit_button_stack   */ false);
        if (disable_action_bar && !disable_popovers)
        {
            bookmarks_button.sensitive = false;
            bookmarks_revealer.hide ();
        }
        modifications_actions_button.show ();
    }

    GLib.Menu changes_pending_menu;
    GLib.Menu quit_delayed_mode_menu;
    private void construct_modifications_actions_button_menu ()
    {
        changes_pending_menu = new GLib.Menu ();
        changes_pending_menu.append (_("Apply all"), "ui.apply-delayed-settings");
        changes_pending_menu.append (_("Dismiss all"), "ui.dismiss-delayed-settings");
        changes_pending_menu.freeze ();

        quit_delayed_mode_menu = new GLib.Menu ();
        quit_delayed_mode_menu.append (_("Quit mode"), "ui.dismiss-delayed-settings");
        quit_delayed_mode_menu.freeze ();

        modifications_actions_button.set_menu_model (changes_pending_menu);
    }

    private void update_modifications_button ()
    {
        if (!disable_action_bar)
            return;

        if (modifications_mode_on)
        {
            quit_button_stack.hide ();
        }
        else
        {
            quit_button_stack.show ();
            if (delay_mode)
                quit_button_stack.set_visible_child (show_modifications_button);
            else
                quit_button_stack.set_visible_child_name ("quit-button");
        }
    }

    internal void set_apply_modifications_button_sensitive (bool new_value)
    {
        if (new_value)
            modifications_actions_button.set_menu_model (changes_pending_menu);
        else
            modifications_actions_button.set_menu_model (quit_delayed_mode_menu);
    }

    /*\
    * * action entries
    \*/

    private void install_action_entries ()
    {
        SimpleActionGroup action_group = new SimpleActionGroup ();
        action_group.add_action_entries (action_entries, this);
        insert_action_group ("headerbar", action_group);
    }

    private const GLib.ActionEntry [] action_entries =
    {
        {   "bookmark-current",   bookmark_current },
        { "unbookmark-current", unbookmark_current }
    };

    private void bookmark_current (/* SimpleAction action, Variant? variant */)
    {
        bookmark_current_path ();
    }

    private void unbookmark_current (/* SimpleAction action, Variant? variant */)
    {
        unbookmark_current_path ();
    }
}
