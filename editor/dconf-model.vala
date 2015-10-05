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
  along with Dconf Editor.  If not, see <http://www.gnu.org/licenses/>.
*/

public struct SchemaKey
{
    public string schema_id;
    public string name;
    public string? summary;
    public string? description;
    public Variant default_value;
    public string type;
    public string range_type;
    public Variant range_content;
}

public class Key : GLib.Object
{
    private SettingsModel model;
    private Directory? parent;

    public string name;
    public string path;
    public string full_name;
    public string cool_text_value ()   // TODO better
    {
        // TODO number of chars after coma for double
        // bool is the only type that permits translation; keep strings for translators
        return type_string == "b" ? (value.get_boolean () ? _("True") : _("False")) : value.print (false);
    }

    public SchemaKey? schema;

    public bool has_schema { get; private set; }
    public string type_string { get; private set; default = "*"; }

    private Variant? _value = null;
    public Variant value
    {
        get
        {
            update_value();
            return _value ?? schema.default_value;  // TODO cannot that error?
        }
        set
        {
            _value = value;
            try
            {
                model.client.write_sync(full_name, value);
            }
            catch (GLib.Error e)
            {
            }
            value_changed();
        }
    }

    public bool is_default
    {
        get { update_value(); return _value == null; }
    }

    public signal void value_changed();

    void item_changed (string key)
    {
        if ((key.has_suffix ("/") && full_name.has_prefix (key)) || key == full_name)
            value_changed ();
    }

    public Key (SettingsModel model, Directory parent, string name, SchemaKey? schema)
    {
        this.model = model;
        this.parent = parent;

        this.name = name;
        path = parent.full_name;
        full_name = path + name;

        this.schema = schema;
        has_schema = schema != null;

        if (has_schema)
            type_string = schema.type;
        else if (value != null)
            type_string = value.get_type_string ();

        model.item_changed.connect (item_changed);
    }

    public void set_to_default()
        requires (has_schema)
    {
        value = null;
    }

    private void update_value()
    {
        _value = model.client.read(full_name);
    }

    public static Variant? get_min (string variant_type)
    {
        switch (variant_type)
        {
            case "y": return new Variant.byte (0);
            case "n": return new Variant.int16 (int16.MIN);
            case "q": return new Variant.uint16 (uint16.MIN);
            case "i": return new Variant.int32 (int32.MIN);
            case "u": return new Variant.uint32 (uint32.MIN);
            case "x": return new Variant.int64 (int64.MIN);
            case "t": return new Variant.uint64 (uint64.MIN);
            case "d": return new Variant.double (double.MIN);
            default:  return null;
        }
    }

    public static Variant? get_max (string variant_type)
    {
        switch (variant_type)
        {
            case "y": return new Variant.byte (255);
            case "n": return new Variant.int16 (int16.MAX);
            case "q": return new Variant.uint16 (uint16.MAX);
            case "i": return new Variant.int32 (int32.MAX);
            case "u": return new Variant.uint32 (uint32.MAX);
            case "x": return new Variant.int64 (int64.MAX);
            case "t": return new Variant.uint64 (uint64.MAX);
            case "d": return new Variant.double (double.MAX);
            default:  return null;
        }
    }
}

public class Directory : GLib.Object
{
    public string name;
    public string full_name;

    public Directory? parent;

    public GLib.ListStore key_model { get; private set; default = new GLib.ListStore (typeof (Key)); }

    public int index
    {
       get { return parent.children.index (this); }
    }

    public GLib.HashTable<string, Directory> _child_map = new GLib.HashTable<string, Directory> (str_hash, str_equal);
    public GLib.List<Directory> children = new GLib.List<Directory> ();

    private GLib.HashTable<string, Key> _key_map = new GLib.HashTable<string, Key> (str_hash, str_equal);

    public Directory (Directory? parent, string name, string full_name)
    {
        this.parent = parent;
        this.name = name;
        this.full_name = full_name;
    }

    public void make_key (SettingsModel model, string name, SchemaKey? schema_key)
    {
        if (_key_map.lookup (name) != null)
            return;

        Key key = new Key (model, this, name, schema_key);
        key_model.insert_sorted (key, (a, b) => { return strcmp (((Key) a).name, ((Key) b).name); });
        _key_map.insert (name, key);
    }
}

public class SettingsModel: GLib.Object, Gtk.TreeModel
{
    public DConf.Client client;
    private Directory root;
    private Directory? view;

    public signal void item_changed (string key);

    void watch_func (DConf.Client client, string path, string[] items, string? tag) {
        foreach (var item in items)
        {   // don't remove that!
            item_changed (path + item);
        }
    }

    public SettingsModel ()
    {
        SettingsSchemaSource settings_schema_source = SettingsSchemaSource.get_default ();
        string [] non_relocatable_schemas;
        string [] relocatable_schemas;
        settings_schema_source.list_schemas (true /* TODO is_recursive = false */, out non_relocatable_schemas, out relocatable_schemas);

        root = new Directory (null, "/", "/");
        view = root;    // if a schema is installed on "/"
        foreach (string settings_schema_id in non_relocatable_schemas)
        {
            SettingsSchema settings_schema = settings_schema_source.lookup (settings_schema_id, true);
            string schema_path = settings_schema.get_path ();
            create_gsettings_views (root, schema_path [1:schema_path.length]);
            create_keys (settings_schema, schema_path);
        }
//        foreach (string settings_schema_id in relocatable_schemas)           // TODO
//            stderr.printf ("%s\n", settings_schema_id);

        client = new DConf.Client ();
        client.changed.connect (watch_func);
        create_dconf_views (root);
        client.watch_sync ("/");
    }

    private void create_keys (SettingsSchema settings_schema, string schema_path)
    {
        string schema_id = settings_schema.get_id ();
        foreach (string key_id in settings_schema.list_keys ())
        {
            SettingsSchemaKey settings_schema_key = settings_schema.get_key (key_id);

            string range_type = settings_schema_key.get_range ().get_child_value (0).get_string (); // don’t put it in the switch, or it fails
            string type;
            switch (range_type)
            {
                case "enum":    type = "<enum>"; break;  // <choices> or enum="", and hopefully <aliases>
                case "flags":   type = "as";     break;  // TODO better
                default:
                case "type":    type = (string) settings_schema_key.get_value_type ().peek_string (); break;
            }

            SchemaKey key = SchemaKey () {
                    schema_id = schema_id,
                    name = key_id,
                    summary = settings_schema_key.get_summary (),
                    description = settings_schema_key.get_description (),
                    default_value = settings_schema_key.get_default_value (),
                    type = type,
                    range_type = range_type,
                    range_content = settings_schema_key.get_range ().get_child_value (1).get_child_value (0)
                };

            view.make_key (this, key_id, key);
        }
    }

    private void create_gsettings_views (Directory parent_view, string remaining)
    {
        if (remaining == "")
            return;

        string [] tokens = remaining.split ("/", 2);
        string path = parent_view.full_name + tokens [0] + "/";

        view = parent_view._child_map.lookup (tokens [0]);
        new_directory_if_needed (parent_view, tokens [0], path);
        create_gsettings_views (view, tokens [1]);
    }

    private void create_dconf_views (Directory parent_view)
    {
        string [] items = client.list (parent_view.full_name);
        for (int i = 0; i < items.length; i++)
        {
            view = parent_view._child_map.lookup (items [i][0:-1]);
            string path = parent_view.full_name + items [i];
            if (DConf.is_dir (path))
            {
                new_directory_if_needed (parent_view, items [i][0:-1], path);
                create_dconf_views (view);
            }
            else
                parent_view.make_key (this, items [i], null);
        }
    }

    private void new_directory_if_needed (Directory parent_view, string name, string path)
    {
        if (view != null)
            return;
        view = new Directory (parent_view, name, path);
        parent_view.children.insert_sorted (view, (a, b) => { return strcmp (((Directory) a).name, ((Directory) b).name); });
        parent_view._child_map.insert (name, view);
    }

    public Gtk.TreeModelFlags get_flags()
    {
        return 0;
    }

    public int get_n_columns()
    {
        return 2;
    }

    public Type get_column_type (int index)
    {
        return index == 0 ? typeof (Directory) : typeof (string);
    }

    private void set_iter (ref Gtk.TreeIter iter, Directory directory)
    {
        iter.stamp = 0;
        iter.user_data = directory;
        iter.user_data2 = directory;
        iter.user_data3 = directory;
    }

    public Directory get_directory (Gtk.TreeIter? iter)
    {
        return iter == null ? root : (Directory) iter.user_data;
    }

    public bool get_iter(out Gtk.TreeIter iter, Gtk.TreePath path)
    {
        iter = Gtk.TreeIter();

        if (!iter_nth_child(out iter, null, path.get_indices()[0]))
            return false;

        for (int i = 1; i < path.get_depth(); i++)
        {
            Gtk.TreeIter parent = iter;
            if (!iter_nth_child(out iter, parent, path.get_indices()[i]))
                return false;
        }

        return true;
    }

    public Gtk.TreePath? get_path(Gtk.TreeIter iter)
    {
        var path = new Gtk.TreePath();
        for (var d = get_directory(iter); d != root; d = d.parent)
            path.prepend_index((int)d.index);
        return path;
    }

    public void get_value(Gtk.TreeIter iter, int column, out Value value)
    {
        if (column == 0)
            value = get_directory(iter);
        else
            value = get_directory(iter).name;
    }

    public bool iter_next(ref Gtk.TreeIter iter)
    {
        var directory = get_directory(iter);
        if (directory.index >= directory.parent.children.length() - 1)
            return false;
        set_iter(ref iter, directory.parent.children.nth_data(directory.index+1));

        return true;
    }

    public bool iter_children(out Gtk.TreeIter iter, Gtk.TreeIter? parent)
    {
        iter = Gtk.TreeIter();

        var directory = get_directory(parent);
        if (directory.children.length() == 0)
            return false;
        set_iter(ref iter, directory.children.nth_data(0));

        return true;
    }

    public bool iter_has_child(Gtk.TreeIter iter)
    {
        return get_directory(iter).children.length() > 0;
    }

    public int iter_n_children(Gtk.TreeIter? iter)
    {
        return (int) get_directory(iter).children.length();
    }

    public bool iter_nth_child(out Gtk.TreeIter iter, Gtk.TreeIter? parent, int n)
    {
        iter = Gtk.TreeIter();

        var directory = get_directory(parent);
        if (n >= directory.children.length())
            return false;
        set_iter(ref iter, directory.children.nth_data(n));

        return true;
    }

    public bool iter_parent(out Gtk.TreeIter iter, Gtk.TreeIter child)
    {
        iter = Gtk.TreeIter();

        var directory = get_directory(child);
        if (directory.parent == root)
            return false;

        set_iter(ref iter, directory.parent);

        return true;
    }

    public void ref_node(Gtk.TreeIter iter)
    {
        get_directory(iter).ref();
    }

    public void unref_node(Gtk.TreeIter iter)
    {
        get_directory(iter).unref();
    }
}
