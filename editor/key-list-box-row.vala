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

const int MAX_ROW_WIDTH = 1000;

private class ListBoxRowWrapper : ListBoxRow
{
    public override void get_preferred_width (out int minimum_width, out int natural_width)
    {
        base.get_preferred_width (out minimum_width, out natural_width);
        natural_width = MAX_ROW_WIDTH;
    }
}

private class RegistryWarning : Grid
{
    public override void get_preferred_width (out int minimum_width, out int natural_width)
    {
        base.get_preferred_width (out minimum_width, out natural_width);
        natural_width = MAX_ROW_WIDTH;
    }
}

private class ListBoxRowHeader : Grid
{
    public override void get_preferred_width (out int minimum_width, out int natural_width)
    {
        base.get_preferred_width (out minimum_width, out natural_width);
        natural_width = MAX_ROW_WIDTH;
    }

    public ListBoxRowHeader (bool is_first_row, string? header_text)
    {
        if (header_text == null)
        {
            if (is_first_row)
                return;
        }
        else
        {
            orientation = Orientation.VERTICAL;

            Label label = new Label ((!) header_text);
            label.visible = true;
            label.halign = Align.START;
            StyleContext context = label.get_style_context ();
            context.add_class ("dim-label");
            context.add_class ("header-label");
            add (label);
        }

        halign = Align.CENTER;

        Separator separator = new Separator (Orientation.HORIZONTAL);
        separator.visible = true;
        separator.hexpand = true;
        add (separator);
    }
}

private abstract class ClickableListBoxRow : EventBox
{
    public bool search_result_mode { public get; construct; default = false; }

    public string full_name { get; construct; }

    /*\
    * * Dismiss popover on window resize
    \*/

    private int width;

    construct
    {
        size_allocate.connect (on_size_allocate);
    }

    private void on_size_allocate (Allocation allocation)
    {
        if (allocation.width == width)
            return;
        hide_right_click_popover ();
        width = allocation.width;
    }

    /*\
    * * right click popover stuff
    \*/

    public ContextPopover? nullable_popover = null;

    public void destroy_popover ()
    {
        if (nullable_popover != null)       // check sometimes not useful
            ((!) nullable_popover).destroy ();
    }

    public void hide_right_click_popover ()
    {
        if (nullable_popover != null)
            ((!) nullable_popover).popdown ();
    }

    public bool right_click_popover_visible ()
    {
        return (nullable_popover != null) && (((!) nullable_popover).visible);
    }
}

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/folder-list-box-row.ui")]
private class FolderListBoxRow : ClickableListBoxRow
{
    [GtkChild] private Label folder_name_label;

    public FolderListBoxRow (string label, string path, bool search_result_mode = false)
    {
        Object (full_name: path, search_result_mode: search_result_mode);
        folder_name_label.set_text (search_result_mode ? path : label);
    }
}

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/key-list-box-row.ui")]
private abstract class KeyListBoxRow : ClickableListBoxRow
{
    [GtkChild] private Grid key_name_and_value_grid;
    [GtkChild] private Label key_name_label;
    [GtkChild] protected Label key_value_label;
    [GtkChild] protected Label key_info_label;
    protected Switch? boolean_switch = null;

    public string key_name    { get; construct; }
    public string type_string { get; construct; }

    private bool _delay_mode = false;
    public bool delay_mode
    {
        protected get
        {
            return _delay_mode;
        }
        set
        {
            _delay_mode = value;
            if (boolean_switch != null)
            {
                if (value)
                {
                    ((!) boolean_switch).hide ();
                    key_value_label.show ();
                }
                else
                {
                    key_value_label.hide ();
                    ((!) boolean_switch).show ();
                }
            }
        }
    }

    public bool small_keys_list_rows
    {
        set
        {
            if (value)
            {
                key_value_label.set_lines (2);
                key_info_label.set_lines (1);
            }
            else
            {
                key_value_label.set_lines (3);
                key_info_label.set_lines (2);
            }
        }
    }

    construct
    {
        if (type_string == "b")
        {
            boolean_switch = new Switch ();
            ((!) boolean_switch).can_focus = false;
            ((!) boolean_switch).valign = Align.CENTER;
            if (!delay_mode)
            {
                key_value_label.hide ();
                ((!) boolean_switch).show ();
            }
            key_name_and_value_grid.attach ((!) boolean_switch, 1, 0, 1, 2);
        }

        key_name_label.set_label (search_result_mode ? full_name : key_name);
    }

    public void toggle_boolean_key ()
    {
        if (boolean_switch == null)
            return;
        ((!) boolean_switch).activate ();
    }

    public void change_dismissed ()
    {
        ModelButton actionable = new ModelButton ();
        actionable.visible = false;
        Variant variant = new Variant.string (full_name);
        actionable.set_detailed_action_name ("ui.dismiss-change(" + variant.print (false) + ")");
        Container child = (Container) get_child ();
        child.add (actionable);
        actionable.clicked ();
        child.remove (actionable);
        actionable.destroy ();
    }

    public void on_delete_call ()
    {
        set_key_value ((this is KeyListBoxRowEditable) ? ((KeyListBoxRowEditable) this).schema_id : "", null);
    }

    public void set_key_value (string schema_or_empty, Variant? new_value)
    {
        ModelButton actionable = new ModelButton ();
        actionable.visible = false;
        Variant variant;
        if (new_value == null)
        {
            if (schema_or_empty != "")
            {
                variant = new Variant ("(ss)", full_name, schema_or_empty);
                actionable.set_detailed_action_name ("bro.set-to-default(" + variant.print (false) + ")");
            }
            else
            {
                variant = new Variant.string (full_name);
                actionable.set_detailed_action_name ("ui.erase(" + variant.print (false) + ")");
            }
        }
        else
        {
            variant = new Variant ("(ssv)", full_name, (schema_or_empty == "" ? ".dconf" : schema_or_empty), (!) new_value);
            actionable.set_detailed_action_name ("bro.set-key-value(" + variant.print (false) + ")");
        }
        Container child = (Container) get_child ();
        child.add (actionable);
        actionable.clicked ();
        child.remove (actionable);
        actionable.destroy ();
    }
}

private class KeyListBoxRowEditableNoSchema : KeyListBoxRow
{
    construct
    {
        get_style_context ().add_class ("dconf-key");

        key_info_label.get_style_context ().add_class ("italic-label");
        key_info_label.set_label (_("No Schema Found"));
    }

    public KeyListBoxRowEditableNoSchema (string _type_string,
                                          bool _delay_mode,
                                          string _key_name,
                                          string _full_name,
                                          bool _search_result_mode = false)
    {
        Object (type_string: _type_string,
                key_name: _key_name,
                delay_mode: _delay_mode,
                full_name: _full_name,
                search_result_mode: _search_result_mode);
    }

    public void update (Variant? key_value)
    {
        StyleContext context = key_value_label.get_style_context ();
        if (key_value == null)
        {
            if (boolean_switch != null) // && !delay_mode?
            {
                ((!) boolean_switch).hide ();
                key_value_label.show ();
            }
            if (!context.has_class ("italic-label")) context.add_class ("italic-label");
            key_value_label.set_label (_("Key erased."));
        }
        else
        {
            if (boolean_switch != null)
            {
                if (!delay_mode)
                {
                    key_value_label.hide ();
                    ((!) boolean_switch).show ();
                }

                bool key_value_boolean = ((!) key_value).get_boolean ();
                Variant switch_variant = new Variant ("(sb)", full_name, !key_value_boolean);
                ((!) boolean_switch).set_action_name ("ui.empty");
                ((!) boolean_switch).set_active (key_value_boolean);
                ((!) boolean_switch).set_detailed_action_name ("bro.toggle-dconf-key-switch(" + switch_variant.print (false) + ")");
            }
            if (context.has_class ("italic-label")) context.remove_class ("italic-label");
            key_value_label.set_label (Key.cool_text_value_from_variant ((!) key_value, type_string));
        }
    }
}

private class KeyListBoxRowEditable : KeyListBoxRow
{
    public GSettingsKey key { get; construct; }

    public string schema_id { get; construct; }

    construct
    {
        get_style_context ().add_class ("gsettings-key");

        if (key.summary != "")
            key_info_label.set_label (key.summary);
        else
        {
            key_info_label.get_style_context ().add_class ("italic-label");
            key_info_label.set_label (_("No summary provided"));
        }

        if (key.warning_conflicting_key)
        {
            if (key.error_hard_conflicting_key)
            {
                get_style_context ().add_class ("hard-conflict");
                if (boolean_switch != null)
                {
                    ((!) boolean_switch).hide ();
                    key_value_label.show ();
                }
                key_value_label.get_style_context ().add_class ("italic-label");
                key_value_label.set_label (_("conflicting keys"));
            }
            else
                get_style_context ().add_class ("conflict");
        }
    }

    public KeyListBoxRowEditable (string _type_string,
                                  GSettingsKey _key,
                                  string _schema_id,
                                  bool _delay_mode,
                                  string _key_name,
                                  string _full_name,
                                  bool _search_result_mode = false)
    {
        Object (type_string: _type_string,
                key: _key,
                schema_id: _schema_id,
                delay_mode: _delay_mode,
                key_name: _key_name,
                full_name: _full_name,
                search_result_mode: _search_result_mode);
    }

    public void update (Variant key_value, bool is_key_default, bool key_default_value_if_bool)
    {
        if (boolean_switch != null)
        {
            bool key_value_boolean = key_value.get_boolean ();
            Variant switch_variant = new Variant ("(ssbb)", full_name, schema_id, !key_value_boolean, key_default_value_if_bool);
            ((!) boolean_switch).set_action_name ("ui.empty");
            ((!) boolean_switch).set_active (key_value_boolean);
            ((!) boolean_switch).set_detailed_action_name ("bro.toggle-gsettings-key-switch(" + switch_variant.print (false) + ")");
        }

        StyleContext css_context = get_style_context ();
        if (is_key_default)
            css_context.remove_class ("edited");
        else
            css_context.add_class ("edited");
        key_value_label.set_label (Key.cool_text_value_from_variant (key_value, type_string));
    }
}

private class ContextPopover : Popover
{
    private GLib.Menu menu = new GLib.Menu ();
    private GLib.Menu current_section;

    private ActionMap current_group = new SimpleActionGroup ();

    // public signals
    public signal void value_changed (Variant? gvariant);
    public signal void change_dismissed ();

    public ContextPopover ()
    {
        new_section_real ();

        insert_action_group ("popmenu", (SimpleActionGroup) current_group);

        bind_model (menu, null);
    }

    /*\
    * * Simple actions
    \*/

    public void new_gaction (string action_name, string action_action)
    {
        string action_text;
        switch (action_name)
        {
            /* Translators: "copy to clipboard" action in the right-click menu on the list of keys */
            case "copy":            action_text = _("Copy");                break;

            /* Translators: "open key-editor page" action in the right-click menu on the list of keys */
            case "customize":       action_text = _("Customize…");          break;

            /* Translators: "reset key value" action in the right-click menu on the list of keys */
            case "default1":        action_text = _("Set to default");      break;

            case "default2": new_multi_default_action (action_action);      return;

            /* Translators: "open key-editor page" action in the right-click menu on the list of keys, when key is hard-conflicting */
            case "detail":          action_text = _("Show details…");       break;

            /* Translators: "dismiss change" action in the right-click menu on a key with pending changes */
            case "dismiss":         action_text = _("Dismiss change");      break;

            /* Translators: "erase key" action in the right-click menu on a key without schema */
            case "erase":           action_text = _("Erase key");           break;

            /* Translators: "open folder" action in the right-click menu on a folder */
            case "open":            action_text = _("Open");                break;

            /* Translators: "open parent folder" action in the right-click menu on a folder in a search result */
            case "open_parent":     action_text = _("Open parent folder");  break;

            /* Translators: "reset recursively" action in the right-click menu on a folder */
            case "recursivereset":  action_text = _("Reset recursively");   break;

            /* Translators: "dismiss change" action in the right-click menu on a key without schema planned to be erased */
            case "unerase":         action_text = _("Do not erase");        break;

            default: assert_not_reached ();
        }
        current_section.append (action_text, action_action);
    }

    public void new_section ()
    {
        current_section.freeze ();
        new_section_real ();
    }
    private void new_section_real ()
    {
        current_section = new GLib.Menu ();
        menu.append_section (null, current_section);
    }

    /*\
    * * Flags
    \*/

    public void create_flags_list (string [] active_flags, string [] all_flags)
    {
        foreach (string flag in all_flags)
            create_flag (flag, flag in active_flags, all_flags);

        finalize_menu ();
    }
    private void create_flag (string flag, bool active, string [] all_flags)
    {
        SimpleAction simple_action = new SimpleAction.stateful (flag, null, new Variant.boolean (active));
        current_group.add_action (simple_action);

        current_section.append (flag, @"popmenu.$flag");

        simple_action.change_state.connect ((gaction, gvariant) => {
                gaction.set_state ((!) gvariant);

                string [] new_flags = new string [0];
                foreach (string iter in all_flags)
                {
                    SimpleAction action = (SimpleAction) current_group.lookup_action (iter);
                    if (((!) action.state).get_boolean ())
                        new_flags += action.name;
                }
                Variant variant = new Variant.strv (new_flags);
                value_changed (variant);
            });
    }

    public void update_flag_status (string flag, bool active)
    {
        SimpleAction simple_action = (SimpleAction) current_group.lookup_action (flag);
        if (active != simple_action.get_state ())
            simple_action.set_state (new Variant.boolean (active));
    }

    /*\
    * * Choices
    \*/

    public GLib.Action create_buttons_list (bool display_default_value, bool delayed_apply_menu, bool planned_change, string settings_type, Variant? value_variant, Variant? range_content_or_null)
    {
        // TODO report bug: if using ?: inside ?:, there's a "g_variant_ref: assertion 'value->ref_count > 0' failed"
        const string ACTION_NAME = "choice";
        string group_dot_action = "popmenu.choice";

        string type_string = settings_type == "<enum>" ? "s" : settings_type;
        VariantType original_type = new VariantType (type_string);
        VariantType nullable_type = new VariantType.maybe (original_type);
        VariantType nullable_nullable_type = new VariantType.maybe (nullable_type);

        Variant variant = new Variant.maybe (original_type, value_variant);
        Variant nullable_variant;
        if (delayed_apply_menu && !planned_change)
            nullable_variant = new Variant.maybe (nullable_type, null);
        else
            nullable_variant = new Variant.maybe (nullable_type, variant);

        GLib.Action action = (GLib.Action) new SimpleAction.stateful (ACTION_NAME, nullable_nullable_type, nullable_variant);
        current_group.add_action (action);

        if (display_default_value)
        {
            bool complete_menu = delayed_apply_menu || planned_change;

            if (complete_menu)
                /* Translators: "no change" option in the right-click menu on a key when on delayed mode */
                current_section.append (_("No change"), @"$group_dot_action(@mm$type_string nothing)");

            if (range_content_or_null != null)
                new_multi_default_action (@"$group_dot_action(@mm$type_string just nothing)");
            else if (complete_menu)
                /* Translators: "erase key" option in the right-click menu on a key without schema when on delayed mode */
                current_section.append (_("Erase key"), @"$group_dot_action(@mm$type_string just nothing)");
        }

        switch (settings_type)
        {
            case "b":
                current_section.append (Key.cool_boolean_text_value (true), @"$group_dot_action(@mmb true)");
                current_section.append (Key.cool_boolean_text_value (false), @"$group_dot_action(@mmb false)");
                break;
            case "<enum>":      // defined by the schema
                Variant range = (!) range_content_or_null;
                uint size = (uint) range.n_children ();
                if (size == 0 || (size == 1 && !display_default_value))
                    assert_not_reached ();
                for (uint index = 0; index < size; index++)
                    current_section.append (range.get_child_value (index).print (false), @"$group_dot_action(@mms '" + range.get_child_value (index).get_string () + "')");        // TODO use int settings.get_enum ()
                break;
            case "mb":
                current_section.append (Key.cool_boolean_text_value (null), @"$group_dot_action(@mmmb just just nothing)");
                current_section.append (Key.cool_boolean_text_value (true), @"$group_dot_action(@mmmb true)");
                current_section.append (Key.cool_boolean_text_value (false), @"$group_dot_action(@mmmb false)");
                break;
            case "y":
            case "q":
            case "u":
            case "t":
                Variant range = (!) range_content_or_null;
                for (uint64 number =  Key.get_variant_as_uint64 (range.get_child_value (0));
                            number <= Key.get_variant_as_uint64 (range.get_child_value (1));
                            number++)
                    current_section.append (number.to_string (), @"$group_dot_action(@mm$type_string $number)");
                break;
            case "n":
            case "i":
            case "h":
            case "x":
                Variant range = (!) range_content_or_null;
                for (int64 number =  Key.get_variant_as_int64 (range.get_child_value (0));
                           number <= Key.get_variant_as_int64 (range.get_child_value (1));
                           number++)
                    current_section.append (number.to_string (), @"$group_dot_action(@mm$type_string $number)");
                break;
            case "()":
                current_section.append ("()", @"$group_dot_action(@mm() ())");
                break;
        }

        ((GLib.ActionGroup) current_group).action_state_changed [ACTION_NAME].connect ((unknown_string, tmp_variant) => {
                Variant? change_variant = tmp_variant.get_maybe ();
                if (change_variant != null)
                    value_changed (((!) change_variant).get_maybe ());
                else
                    change_dismissed ();
            });

        finalize_menu ();

        return action;
    }

    /*\
    * * Multi utilities
    \*/

    private void new_multi_default_action (string action)
    {
        /* Translators: "reset key value" option of a multi-choice list (checks or radios) in the right-click menu on the list of keys */
        current_section.append (_("Default value"), action);
    }

    private void finalize_menu ()
        requires (menu.is_mutable ())  // should just "return;" then if function is made public
    {
        current_section.freeze ();
        menu.freeze ();
    }
}
