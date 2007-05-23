-----------------------------------------------------------------------
--                               G P S                               --
--                                                                   --
--                      Copyright (C) 2006-2007                      --
--                              AdaCore                              --
--                                                                   --
-- GPS is Free  software;  you can redistribute it and/or modify  it --
-- under the terms of the GNU General Public License as published by --
-- the Free Software Foundation; either version 2 of the License, or --
-- (at your option) any later version.                               --
--                                                                   --
-- This program is  distributed in the hope that it will be  useful, --
-- but  WITHOUT ANY WARRANTY;  without even the  implied warranty of --
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU --
-- General Public License for more details. You should have received --
-- a copy of the GNU General Public License along with this program; --
-- if not,  write to the  Free Software Foundation, Inc.,  59 Temple --
-- Place - Suite 330, Boston, MA 02111-1307, USA.                    --
-----------------------------------------------------------------------

with Ada.Strings.Less_Case_Insensitive;
with Ada.Strings.Equal_Case_Insensitive;
with GNAT.OS_Lib;                use GNAT.OS_Lib;

with Glib;                       use Glib;
with Glib.Properties;
with Gtk.Cell_Renderer;
with Gtk.Cell_Renderer_Text;     use Gtk.Cell_Renderer_Text;
with Gtk.Cell_Renderer_Pixbuf;   use Gtk.Cell_Renderer_Pixbuf;
with Gtk.Cell_Renderer_Progress; use Gtk.Cell_Renderer_Progress;
with Gtk.Scrolled_Window;        use Gtk.Scrolled_Window;
with Gtk.Enums;                  use Gtk.Enums;
with Gtk.Stock;                  use Gtk.Stock;
with Gtk.Window;                 use Gtk.Window;
with Gtk.Menu_Item;              use Gtk.Menu_Item;
with Gtk.Tree_Selection;         use Gtk.Tree_Selection;
with Gtk.Button;                 use Gtk.Button;
with Gtk.Label;                  use Gtk.Label;
with Gtk.Object;                 use Gtk.Object;
with Gtk.Image;                  use Gtk.Image;
with Gtkada.MDI;                 use Gtkada.MDI;
with Gtkada.Handlers;            use Gtkada.Handlers;
with Gtkada.Dialogs;             use Gtkada.Dialogs;

with GPS.Kernel.Project;         use GPS.Kernel.Project;
with GPS.Kernel.Styles;          use GPS.Kernel.Styles;
with GPS.Kernel.Standard_Hooks;  use GPS.Kernel.Standard_Hooks;
with GPS.Kernel.Contexts;        use GPS.Kernel.Contexts;
with GPS.Kernel.Console;
with GPS.Location_View;          use GPS.Location_View;

with Basic_Types;                use Basic_Types;
with Projects.Registry;          use Projects.Registry;
with Language_Handlers;          use Language_Handlers;
with Language;                   use Language;
with Language.Tree;              use Language.Tree;
with Language.Tree.Database;
with Entities;                   use Entities;
with Code_Coverage;              use Code_Coverage;
with Code_Analysis_Tree_Model;   use Code_Analysis_Tree_Model;

package body Code_Analysis_Module is

   Src_File_Cst : aliased   constant String := "src";
   --  Constant String that represents the name of the source file parameter
   --  of the GPS.CodeAnalysis.add_gcov_file_info subprogram
   Cov_File_Cst : aliased   constant String := "cov";
   --  Constant String that represents the name of the .gcov file parameter
   --  of the GPS.CodeAnalysis.add_gcov_file_info subprogram
   Prj_File_Cst : aliased   constant String := "prj";
   --  Constant String that represents the name of the .gpr file parameter
   --  of the GPS.CodeAnalysis.add_gcov_project_info subprogram
   Gcov_Extension_Cst :     constant String := ".gcov";
   --  Constant String that represents the extension of GCOV files
   Progress_Bar_Width_Cst : constant Gint   := 150;
   --  Constant used to set the width of the progress bars of the analysis
   --  report

   Line_Info_Cst  : constant String := "Coverage Analysis";
   --  Name of the text info column used for the annotations
   Line_Icons_Cst : constant String := "Coverage Icons";
   --  Name of the pixmap column used for the annotations

   Binary_Coverage_Trace : constant Debug_Handle :=
                             Create ("BINARY_COVERAGE_MODE", On);
   Binary_Coverage_Mode : Boolean;
   --  Boolean that allows to determine wether we are in binary coverage mode
   --  or not.

   -----------------------
   -- Create_From_Shell --
   -----------------------

   procedure Create_From_Shell
     (Data    : in out Callback_Data'Class;
      Command : String)
   is
      pragma Unreferenced (Command);
      Instance  : Class_Instance;
   begin
      Instance := Nth_Arg (Data, 1, Code_Analysis_Module_ID.Class);
      Initialize_Instance (Instance);
   exception
      when E : others => Trace (Exception_Handle, E);
   end Create_From_Shell;

   ----------------------
   -- Create_From_Menu --
   ----------------------

   procedure Create_From_Menu
     (Widget : access Gtk.Widget.Gtk_Widget_Record'Class)
   is
      Dummy : Class_Instance;
      pragma Unreferenced (Widget, Dummy);
   begin
      Dummy := Create_Instance;
   exception
      when E : others => Trace (Exception_Handle, E);
   end Create_From_Menu;

   ---------------------
   -- Create_Instance --
   ---------------------

   function Create_Instance return Class_Instance is
      Scripts  : constant Scripting_Language_Array :=
                   Get_Scripting_Languages (Code_Analysis_Module_ID.Kernel);
      Instance : Class_Instance := New_Instance
        (Scripts (Scripts'First), Code_Analysis_Module_ID.Class);
   begin
      Initialize_Instance (Instance);
      return Instance;
   end Create_Instance;

   -------------------------
   -- Initialize_Instance --
   -------------------------

   procedure Initialize_Instance (Instance : in out Class_Instance) is
      Property : constant Code_Analysis_Property
        := new Code_Analysis_Property_Record;
      Date     : Time;
   begin
      Date := Clock;
      Property.Date := Date;
      Property.Instance_Name :=
        new String'(-"Analysis" & Integer'Image
                    (Integer (Code_Analysis_Module_ID.Instances.Length + 1)));
      Property.Projects := new Project_Maps.Map;
      GPS.Kernel.Scripts.Set_Property
        (Instance, Code_Analysis_Cst_Str,
         Instance_Property_Record (Property.all));
      Code_Analysis_Module_ID.Instances.Insert (Instance);

      --  Loading the Pixbufs if it has not already been done
      --  We do it here because it can't be done at loading module time
      if Code_Analysis_Module_ID.Project_Pixbuf = null then
         Code_Analysis_Module_ID.Project_Pixbuf := Render_Icon
           (Get_Main_Window (Code_Analysis_Module_ID.Kernel),
            "gps-project-closed", Gtk.Enums.Icon_Size_Menu);
         Code_Analysis_Module_ID.File_Pixbuf := Render_Icon
           (Get_Main_Window (Code_Analysis_Module_ID.Kernel),
            "gps-file", Gtk.Enums.Icon_Size_Menu);
         Code_Analysis_Module_ID.Subp_Pixbuf := Render_Icon
           (Get_Main_Window (Code_Analysis_Module_ID.Kernel),
            "gps-entity-subprogram", Gtk.Enums.Icon_Size_Menu);
         Code_Analysis_Module_ID.Warn_Pixbuf := Render_Icon
           (Get_Main_Window (Code_Analysis_Module_ID.Kernel),
            "gps-warning", Gtk.Enums.Icon_Size_Menu);
      end if;
   end Initialize_Instance;

   -------------------------------------
   -- Add_Gcov_File_Info_From_Context --
   -------------------------------------

   procedure Add_Gcov_File_Info_From_Context
     (Widget      : access Glib.Object.GObject_Record'Class;
      Cont_N_Inst : Context_And_Instance)
   is
      pragma Unreferenced (Widget);
      Property : Code_Analysis_Property_Record;
      Prj_Name : constant Project_Type :=
                   Project_Information (Cont_N_Inst.Context);
      Prj_Node : Project_Access;
      Src_File : constant VFS.Virtual_File :=
                   File_Information (Cont_N_Inst.Context);
      Cov_File : VFS.Virtual_File;
      Instance : Class_Instance;
   begin
      if Cont_N_Inst.Instance = No_Class_Instance then
         Instance := Create_Instance;
      else
         Instance := Cont_N_Inst.Instance;
      end if;

      Property := Code_Analysis_Property_Record
        (Get_Property (Instance, Code_Analysis_Cst_Str));
      Prj_Node := Get_Or_Create (Property.Projects, Prj_Name);
      Cov_File := Create (Object_Path (Prj_Name, False, False) &
                              "/" & Base_Name (Src_File) & Gcov_Extension_Cst);

      if not Is_Regular_File (Cov_File) then
         GPS.Kernel.Console.Insert
           (Code_Analysis_Module_ID.Kernel,
            -"There is no loadable GCOV information" &
            (-" associated with " & Base_Name (Src_File)),
            Mode => GPS.Kernel.Console.Error);

         declare
            File_Node : constant Code_Analysis.File_Access
              := Get_Or_Create (Prj_Node, Src_File);
         begin
            Set_Error (File_Node, File_Not_Found);
            --  Set an empty line array in order to make File_Node a valid
            --  Code_Analysis node
            File_Node.Lines := new Line_Array (1 .. 1);
         end;
      else
         Add_Gcov_File_Info (Src_File, Cov_File, Prj_Node);
         Compute_Project_Coverage (Prj_Node);
      end if;

      --  Build/Refresh Report of Analysis
      Show_Analysis_Report
        (Context_And_Instance'(Cont_N_Inst.Context, Instance), Property);
   exception
      when E : others => Trace (Exception_Handle, E);
   end Add_Gcov_File_Info_From_Context;

   -----------------------------------
   -- Add_Gcov_File_Info_From_Shell --
   -----------------------------------

   procedure Add_Gcov_File_Info_From_Shell
     (Data    : in out Callback_Data'Class;
      Command : String)
   is
      pragma Unreferenced (Command);
      Property : Code_Analysis_Property_Record;
      Instance : Class_Instance;
      Context  : Selection_Context;
      Src_Inst : Class_Instance;
      Cov_Inst : Class_Instance;
      Src_File : VFS.Virtual_File;
      Cov_File : VFS.Virtual_File;
      Prj_Name : Project_Type;
      Prj_Node : Project_Access;
   begin
      Instance := Nth_Arg (Data, 1, Code_Analysis_Module_ID.Class);
      Property := Code_Analysis_Property_Record
        (Get_Property (Instance, Code_Analysis_Cst_Str));
      Name_Parameters (Data, (2 => Src_File_Cst'Access,
                              3 => Cov_File_Cst'Access));
      Src_Inst := Nth_Arg
        (Data, 2, Get_File_Class (Code_Analysis_Module_ID.Kernel),
         Default => No_Class_Instance, Allow_Null => True);

      if Src_Inst = No_Class_Instance then
         Src_File := VFS.No_File;
      else
         Src_File := Get_Data (Src_Inst);
      end if;

      if not Is_Regular_File (Src_File) then
         Set_Error_Msg (Data, -"The name given for 'src' file is wrong");
         return;
      end if;

      Cov_Inst := Nth_Arg
        (Data, 3, Get_File_Class (Code_Analysis_Module_ID.Kernel),
         Default => No_Class_Instance, Allow_Null => True);

      if Cov_Inst = No_Class_Instance then
         Cov_File := VFS.No_File;
      else
         Cov_File := Get_Data (Cov_Inst);
      end if;

      Prj_Name  := Get_Project_From_File
        (Get_Registry (Code_Analysis_Module_ID.Kernel).all, Src_File);
      Prj_Node  := Get_Or_Create (Property.Projects, Prj_Name);

      if not Is_Regular_File (Cov_File) then
         Set_Error_Msg (Data, -"The name given for 'cov' file is wrong");

         declare
            File_Node : constant Code_Analysis.File_Access
              := Get_Or_Create (Prj_Node, Src_File);
         begin
            Set_Error (File_Node, File_Not_Found);
            --  Set an empty line array in order to make File_Node a valid
            --  Code_Analysis node
            File_Node.Lines := new Line_Array (1 .. 1);
         end;
         return;
      end if;

      Add_Gcov_File_Info (Src_File, Cov_File, Prj_Node);
      Compute_Project_Coverage (Prj_Node);
      --  Build/Refresh Report of Analysis
      Context := Get_Current_Context (Code_Analysis_Module_ID.Kernel);
      Set_File_Information
        (Context, Project => Prj_Name, File => Src_File);
      Show_Analysis_Report
        (Context_And_Instance'(Context, Instance), Property);
   exception
      when E : others => Trace (Exception_Handle, E);
   end Add_Gcov_File_Info_From_Shell;

   ------------------------
   -- Add_Gcov_File_Info --
   ------------------------

   procedure Add_Gcov_File_Info
     (Src_File     : VFS.Virtual_File;
      Cov_File     : VFS.Virtual_File;
      Project_Node : Project_Access)
   is
      use Language.Tree.Database;
      File_Contents : GNAT.Strings.String_Access;
      Prj_Called    : Positive;
      Success       : Boolean;
      File_Node     : constant Code_Analysis.File_Access
        := Get_Or_Create (Project_Node, Src_File);
      Handler       : constant Language_Handler
        := Get_Language_Handler (Code_Analysis_Module_ID.Kernel);
      Database      : constant Construct_Database_Access
        := Get_Construct_Database (Code_Analysis_Module_ID.Kernel);
      Tree_Lang     : constant Tree_Language_Access
        := Get_Tree_Language_From_File (Handler, Src_File, False);
      Data_File     : constant Structured_File_Access
        := Language.Tree.Database.Get_Or_Create
          (Db   => Database,
           File => Src_File,
           Lang => Tree_Lang);
   begin
      if File_Time_Stamp (Src_File) > File_Time_Stamp (Cov_File) then
         GPS.Kernel.Console.Insert
           (Code_Analysis_Module_ID.Kernel, Base_Name (Src_File) &
         (-" has been modified since GCOV information were generated.") &
         (-" Skipped."),
            Mode => GPS.Kernel.Console.Error);
         Set_Error (File_Node, File_Corrupted);
         --  Set an empty line array in order to make File_Node a valid
         --  Code_Analysis node
         File_Node.Lines := new Line_Array (1 .. 1);
      else
         File_Contents := Read_File (Cov_File);
         Add_File_Info (File_Node, File_Contents);

         if File_Node.Analysis_Data.Coverage_Data.Status = Valid and then
           Project_Node.Analysis_Data.Coverage_Data = null then

            Get_Runs_Info_From_File
              (File_Node, File_Contents, Prj_Called, Success);

            if Success then
               Project_Node.Analysis_Data.Coverage_Data :=
                 new Subprogram_Coverage;
               Subprogram_Coverage
                 (Project_Node.Analysis_Data.Coverage_Data.all).Called :=
                 Prj_Called;
            end if;
            --  Check for project Called info
         end if;

         if File_Node.Analysis_Data.Coverage_Data.Status = Valid then
            Add_Subprogram_Info (File_Node, Data_File);
         end if;

         Free (File_Contents);
      end if;
   end Add_Gcov_File_Info;

   ----------------------------------------
   -- Add_Gcov_Project_Info_From_Context --
   ----------------------------------------

   procedure Add_Gcov_Project_Info_From_Context
     (Widget      : access Glib.Object.GObject_Record'Class;
      Cont_N_Inst : Context_And_Instance)
   is
      pragma Unreferenced (Widget);
      Property : Code_Analysis_Property_Record;
      Instance : Class_Instance;
      Prj_Node : Project_Access;
      Prj_Name : constant Project_Type :=
                   Project_Information (Cont_N_Inst.Context);
   begin
      if Cont_N_Inst.Instance = No_Class_Instance then
         Instance := Create_Instance;
      else
         Instance := Cont_N_Inst.Instance;
      end if;

      Property := Code_Analysis_Property_Record
        (Get_Property (Instance, Code_Analysis_Cst_Str));
      Prj_Node := Get_Or_Create (Property.Projects, Prj_Name);
      Add_Gcov_Project_Info (Prj_Node);
      --  Build/Refresh Report of Analysis
      Show_Analysis_Report
        (Context_And_Instance'(Cont_N_Inst.Context, Instance), Property);
   exception
      when E : others => Trace (Exception_Handle, E);
   end Add_Gcov_Project_Info_From_Context;

   --------------------------------------
   -- Add_Gcov_Project_Info_From_Shell --
   --------------------------------------

   procedure Add_Gcov_Project_Info_From_Shell
     (Data    : in out Callback_Data'Class;
      Command : String)
   is
      pragma Unreferenced (Command);
      Property : Code_Analysis_Property_Record;
      Instance : Class_Instance;
      Context  : Selection_Context;
      Prj_Inst : Class_Instance;
      Prj_File : VFS.Virtual_File;
      Prj_Name : Project_Type;
      Prj_Node : Project_Access;
   begin
      Instance := Nth_Arg (Data, 1, Code_Analysis_Module_ID.Class);
      Property := Code_Analysis_Property_Record
        (Get_Property (Instance, Code_Analysis_Cst_Str));
      Name_Parameters (Data, (2 => Prj_File_Cst'Access));
      Prj_Inst := Nth_Arg
        (Data, 2, Get_File_Class (Code_Analysis_Module_ID.Kernel),
         Default => No_Class_Instance, Allow_Null => True);

      if Prj_Inst = No_Class_Instance then
         Prj_File := VFS.No_File;
      else
         Prj_File := Get_Data (Prj_Inst);
      end if;

      if not Is_Regular_File (Prj_File) then
         Set_Error_Msg (Data, -"The name given for 'prj' file is wrong");
         return;
      end if;

      Prj_Name  := Load_Or_Find
        (Get_Registry (Code_Analysis_Module_ID.Kernel).all,
         Locale_Full_Name (Prj_File));
      Prj_Node  := Get_Or_Create (Property.Projects, Prj_Name);
      Add_Gcov_Project_Info (Prj_Node);

      --  Build/Refresh Report of Analysis
      Context := Get_Current_Context (Code_Analysis_Module_ID.Kernel);
      Set_File_Information (Context, Project => Prj_Name);
      Show_Analysis_Report
        (Context_And_Instance'(Context, Instance), Property);
   exception
      when E : others => Trace (Exception_Handle, E);
   end Add_Gcov_Project_Info_From_Shell;

   ---------------------------
   -- Add_Gcov_Project_Info --
   ---------------------------

   procedure Add_Gcov_Project_Info (Prj_Node : Project_Access) is
      Src_Files : VFS.File_Array_Access;
      Src_File  : VFS.Virtual_File;
      Cov_File  : VFS.Virtual_File;
   begin
      --  get every source files of the project
      --  check if they are associated with gcov info
      --  load their info
      Src_Files := Get_Source_Files (Prj_Node.Name, Recursive => False);

      for J in Src_Files'First .. Src_Files'Last loop
         Src_File := Src_Files (J);
         Cov_File := Create (Object_Path (Prj_Node.Name, False, False) &
                             "/" & Base_Name (Src_File) & Gcov_Extension_Cst);

         if Is_Regular_File (Cov_File) then
            Add_Gcov_File_Info (Src_File, Cov_File, Prj_Node);
         else
            GPS.Kernel.Console.Insert
              (Code_Analysis_Module_ID.Kernel,
               -"There is no loadable GCOV information" &
               (-" associated with " & Base_Name (Src_File)),
               Mode => GPS.Kernel.Console.Error);

            declare
               File_Node : constant Code_Analysis.File_Access
                 := Get_Or_Create (Prj_Node, Src_File);
            begin
               Set_Error (File_Node, File_Not_Found);
               --  Set an empty line array in order to make File_Node a valid
               --  Code_Analysis node
               File_Node.Lines := new Line_Array (1 .. 1);
            end;
         end if;
      end loop;

      Compute_Project_Coverage (Prj_Node);
   exception
      when E : others => Trace (Exception_Handle, E);
   end Add_Gcov_Project_Info;

   --------------------------------------------
   -- Add_All_Gcov_Project_Info_From_Context --
   --------------------------------------------

   procedure Add_All_Gcov_Project_Info_From_Context
     (Widget      : access Glib.Object.GObject_Record'Class;
      Cont_N_Inst : Context_And_Instance)
   is
      pragma Unreferenced (Widget);
      Property : Code_Analysis_Property_Record;
      Instance : Class_Instance;
      Prj_Iter : Imported_Project_Iterator;
      Prj_Node : Project_Access;
      Prj_Name : constant Project_Type :=
                   Project_Information (Cont_N_Inst.Context);
   begin
      if Cont_N_Inst.Instance = No_Class_Instance then
         Instance := Create_Instance;
      else
         Instance := Cont_N_Inst.Instance;
      end if;

      Property := Code_Analysis_Property_Record
        (Get_Property (Instance, Code_Analysis_Cst_Str));
      Prj_Iter := Start (Prj_Name);

      loop
         exit when Current (Prj_Iter) = No_Project;
         Prj_Node := Get_Or_Create (Property.Projects, Current (Prj_Iter));
         Add_Gcov_Project_Info (Prj_Node);
         Next (Prj_Iter);
      end loop;

      --  Build/Refresh Report of Analysis
      Show_Analysis_Report
        (Context_And_Instance'(No_Context, Instance), Property);
   exception
      when E : others => Trace (Exception_Handle, E);
   end Add_All_Gcov_Project_Info_From_Context;

   ------------------------------------------
   -- Add_All_Gcov_Project_Info_From_Shell --
   ------------------------------------------

   procedure Add_All_Gcov_Project_Info_From_Shell
     (Data    : in out Callback_Data'Class;
      Command : String)
   is
      pragma Unreferenced (Command);
      Property : Code_Analysis_Property_Record;
      Instance : Class_Instance;
      Prj_Name : Project_Type;
      Prj_Node : Project_Access;
      Prj_Iter : Imported_Project_Iterator;
   begin
      Instance := Nth_Arg (Data, 1, Code_Analysis_Module_ID.Class);
      Property := Code_Analysis_Property_Record
        (Get_Property (Instance, Code_Analysis_Cst_Str));

      Prj_Name := Get_Project (Code_Analysis_Module_ID.Kernel);
      Prj_Iter := Start (Prj_Name);

      loop
         exit when Current (Prj_Iter) = No_Project;
         Prj_Node := Get_Or_Create (Property.Projects, Current (Prj_Iter));
         Add_Gcov_Project_Info (Prj_Node);
         Next (Prj_Iter);
      end loop;

      --  Build/Refresh Report of Analysis
      Show_Analysis_Report
        (Context_And_Instance'(No_Context, Instance), Property);
   exception
      when E : others => Trace (Exception_Handle, E);
   end Add_All_Gcov_Project_Info_From_Shell;

   -------------------------------------------------------
   -- List_Lines_Not_Covered_In_All_Projects_From_Shell --
   -------------------------------------------------------

   procedure List_Lines_Not_Covered_In_All_Projects_From_Shell
     (Data    : in out Callback_Data'Class;
      Command : String)
   is
      pragma Unreferenced (Command);
      Property : Code_Analysis_Property_Record;
      Instance : Class_Instance;
   begin
      Instance := Nth_Arg (Data, 1, Code_Analysis_Module_ID.Class);
      Property := Code_Analysis_Property_Record
        (Get_Property (Instance, Code_Analysis_Cst_Str));
      List_Lines_Not_Covered_In_All_Projects (Property);
   exception
      when E : others => Trace (Exception_Handle, E);
   end List_Lines_Not_Covered_In_All_Projects_From_Shell;

   ------------------------------------------------------
   -- List_Lines_Not_Covered_In_All_Projects_From_Menu --
   ------------------------------------------------------

   procedure List_Lines_Not_Covered_In_All_Projects_From_Menu
     (Widget      : access Glib.Object.GObject_Record'Class;
      Cont_N_Inst : Context_And_Instance)
   is
      pragma Unreferenced (Widget);
      Property : constant Code_Analysis_Property_Record
        := Code_Analysis_Property_Record
          (Get_Property (Cont_N_Inst.Instance, Code_Analysis_Cst_Str));
   begin
      List_Lines_Not_Covered_In_All_Projects (Property);
   exception
      when E : others => Trace (Exception_Handle, E);
   end List_Lines_Not_Covered_In_All_Projects_From_Menu;

   --------------------------------------------
   -- List_Lines_Not_Covered_In_All_Projects --
   --------------------------------------------

   procedure List_Lines_Not_Covered_In_All_Projects
     (Property : Code_Analysis_Property_Record)
   is
      use Project_Maps;
      Map_Cur  : Project_Maps.Cursor;
      Sort_Arr : Project_Array (1 .. Integer (Property.Projects.Length));
   begin
      Map_Cur  := Property.Projects.First;

      for J in Sort_Arr'Range loop
         Sort_Arr (J) := Element (Map_Cur);
         Next (Map_Cur);
      end loop;

      Sort_Projects (Sort_Arr);

      for J in Sort_Arr'Range loop
         List_Lines_Not_Covered_In_Project (Sort_Arr (J));
      end loop;
   end List_Lines_Not_Covered_In_All_Projects;

   -------------------------------------
   -- Show_Analysis_Report_From_Shell --
   -------------------------------------

   procedure Show_Analysis_Report_From_Shell
     (Data    : in out Callback_Data'Class;
      Command : String)
   is
      pragma Unreferenced (Command);
      Instance : Class_Instance;
      Property : Code_Analysis_Property_Record;
   begin
      Instance := Nth_Arg (Data, 1, Code_Analysis_Module_ID.Class);
      Property := Code_Analysis_Property_Record
        (Get_Property (Instance, Code_Analysis_Cst_Str));
      Show_Analysis_Report
        (Context_And_Instance'(No_Context, Instance), Property);
   exception
      when E : others => Trace (Exception_Handle, E);
   end Show_Analysis_Report_From_Shell;

   ------------------------------------
   -- Show_Analysis_Report_From_Menu --
   ------------------------------------

   procedure Show_Analysis_Report_From_Menu
     (Widget      : access Glib.Object.GObject_Record'Class;
      Cont_N_Inst : Context_And_Instance)
   is
      pragma Unreferenced (Widget);
      Property : Code_Analysis_Property_Record := Code_Analysis_Property_Record
        (Get_Property (Cont_N_Inst.Instance, Code_Analysis_Cst_Str));
   begin
      Show_Analysis_Report (Cont_N_Inst, Property);
   exception
      when E : others => Trace (Exception_Handle, E);
   end Show_Analysis_Report_From_Menu;

   ------------------------------------------
   -- Show_Empty_Analysis_Report_From_Menu --
   ------------------------------------------

   procedure Show_Empty_Analysis_Report_From_Menu
     (Widget : access Glib.Object.GObject_Record'Class)
   is
      pragma Unreferenced (Widget);
      Instance : constant Class_Instance := Create_Instance;
      Property : Code_Analysis_Property_Record := Code_Analysis_Property_Record
        (Get_Property (Instance, Code_Analysis_Cst_Str));
   begin
      Show_Empty_Analysis_Report (Instance, Property);
      GPS.Kernel.Scripts.Set_Property
        (Instance, Code_Analysis_Cst_Str, Instance_Property_Record (Property));
   exception
      when E : others => Trace (Exception_Handle, E);
   end Show_Empty_Analysis_Report_From_Menu;

   --------------------------------
   -- Show_Empty_Analysis_Report --
   --------------------------------

   procedure Show_Empty_Analysis_Report
     (Instance : Class_Instance;
      Property : in out Code_Analysis_Property_Record) is
   begin
      if Property.View /= null and then Property.View.Error_Box = null then
         Close_Child (Property.Child, Force => True);
      end if;

      if Property.View = null then
         Build_Analysis_Report (Instance, Property, Is_Error => True);
      end if;

      Raise_Child (Property.Child);
   end Show_Empty_Analysis_Report;

   --------------------------------------
   -- First_Project_With_Coverage_Data --
   --------------------------------------

   function First_Project_With_Coverage_Data
     (Property : Code_Analysis_Property_Record) return Project_Type
   is
      use Project_Maps;
      Prj_Node : Code_Analysis.Project_Access;
      Prj_Cur  : Project_Maps.Cursor := Property.Projects.First;
   begin
      if Prj_Cur /= No_Element then
         Prj_Node := Element (Prj_Cur);
      else
         return No_Project;
      end if;

      loop
         exit when Prj_Node.Analysis_Data.Coverage_Data /= null
           or else Prj_Cur = No_Element;
         Prj_Node := Element (Prj_Cur);
         Next (Prj_Cur);
      end loop;

      if Prj_Cur /= No_Element then
         return Prj_Node.Name;
      else
         return No_Project;
      end if;
   end First_Project_With_Coverage_Data;

   ---------------------------
   -- Get_Iter_From_Context --
   ---------------------------

   function Get_Iter_From_Context
     (Context : Selection_Context;
      Model   : Gtk_Tree_Store) return Gtk_Tree_Iter
   is
      Iter    : Gtk_Tree_Iter := Get_Iter_First (Model);
      Num_Col : constant Gint := 1;
   begin
      if Iter /= Null_Iter then
         if not Has_Child (Model, Iter) then
            --  So we are in a flat list
            if Has_Entity_Name_Information (Context) then
               declare
                  Entity : constant Entities.Entity_Information :=
                             Get_Entity (Context);
               begin
                  if (Entity /= null
                      and then Is_Subprogram (Entity))
                    or else Get_Creator (Context) = Abstract_Module_ID
                    (Code_Analysis_Module_ID) then
                     --  So we have a subprogram information
                     --  Find in the list the context's subprogram
                     loop
                        exit when Get_String (Model, Iter, Num_Col) =
                          Entity_Name_Information (Context);
                        Next (Model, Iter);
                     end loop;
                  end if;
               end;
            elsif Has_File_Information (Context) then
               --  Find in the list the context's file
               loop
                  exit when Get_String (Model, Iter, Num_Col) =
                    Base_Name (File_Information (Context));
                  Next (Model, Iter);
               end loop;
            else
               --  Find in the list the context's project
               loop
                  exit when Get_String (Model, Iter, Num_Col) =
                    Project_Name (Project_Information (Context));
                  Next (Model, Iter);
               end loop;
            end if;
         else
            --  Find in the tree the context's project
            loop
               exit when Get_String (Model, Iter, Num_Col) =
                 Project_Name (Project_Information (Context));
               Next (Model, Iter);
            end loop;

            if Has_File_Information (Context) then
               --  So we also have file information
               Iter := Children (Model, Iter);

               --  Find in the tree the context's file
               loop
                  exit when Get_String (Model, Iter, Num_Col) =
                    Base_Name (File_Information (Context));
                  Next (Model, Iter);
               end loop;
            end if;

            if Has_Entity_Name_Information (Context) then
               declare
                  Entity : constant Entities.Entity_Information :=
                             Get_Entity (Context);
               begin
                  if (Entity /= null
                      and then Is_Subprogram (Entity))
                    or else Get_Creator (Context) = Abstract_Module_ID
                    (Code_Analysis_Module_ID) then
                     --  So we have a subprogram information
                     Iter := Children (Model, Iter);
                     --  Find in the tree the context's subprogram
                     loop
                        exit when Get_String (Model, Iter, Num_Col) =
                          Entity_Name_Information (Context);
                        Next (Model, Iter);
                     end loop;
                  end if;
               end;
            end if;
         end if;
      end if;

      return Iter;
   end Get_Iter_From_Context;

   --------------------------
   -- Show_Analysis_Report --
   --------------------------

   procedure Show_Analysis_Report
     (Cont_N_Inst  : Context_And_Instance;
      Property     : in out Code_Analysis_Property_Record;
      Raise_Report : Boolean := True)
   is
      Local_Context : Selection_Context;
      Iter          : Gtk_Tree_Iter;
      Path          : Gtk_Tree_Path;
   begin

      --------------------------------------
      --  Check for analysis information  --
      --------------------------------------

      if Local_Context = No_Context then
         Local_Context := Check_Context (No_Context);
      end if;

      declare
         Prj_Name : Project_Type;
         Prj_Node : Code_Analysis.Project_Access;
      begin
         Prj_Node := Get_Or_Create
           (Property.Projects, Project_Information (Local_Context));

         if Prj_Node.Analysis_Data.Coverage_Data = null then
            --  If the current context's project has no coverage data, it has
            --  to be modified or an erro message is shown
            Prj_Name := First_Project_With_Coverage_Data (Property);

            if Prj_Name /= No_Project then
               --  Set in the context the 1st project that has analysis
               --  data
               Set_File_Information
                 (Local_Context, Project => Prj_Name);
            else
               Show_Empty_Analysis_Report
                 (Cont_N_Inst.Instance, Property);
               return;
            end if;
         end if;
      end;

      --  Here we have a context that point on elements that will be added to
      --  the report of analysis

      --------------------------
      --  Building the report --
      --------------------------

      if Property.View = null then
         Build_Analysis_Report (Cont_N_Inst.Instance, Property);
      elsif Property.View.Error_Box /= null then
         Destroy_Cb (Property.View.Error_Box);
         Property.View.Error_Box := null;
      end if;

      Clear (Property.View.Model);
      Iter := Get_Iter_First (Property.View.Model);
      Fill_Iter
        (Property.View.Model, Iter, Property.Projects, Binary_Coverage_Mode);

      --------------------------------------
      --  Selection of the context caller --
      --------------------------------------

      Iter := Get_Iter_From_Context (Local_Context, Property.View.Model);

      if Iter = Null_Iter then
         Show_Empty_Analysis_Report (Cont_N_Inst.Instance, Property);
         return;
      end if;

      Path := Get_Path (Property.View.Model, Iter);
      Collapse_All (Property.View.Tree);
      Expand_To_Path (Property.View.Tree, Path);
      Select_Path (Get_Selection (Property.View.Tree), Path);
      Path_Free (Path);

      if Raise_Report then
         Raise_Child (Property.Child);
      end if;
   end Show_Analysis_Report;

   ---------------------------
   -- Build_Analysis_Report --
   ---------------------------

   procedure Build_Analysis_Report
     (Instance : Class_Instance;
      Property : in out Code_Analysis_Property_Record;
      Is_Error : Boolean := False)
   is
      Scrolled    : Gtk_Scrolled_Window;
      Text_Render : Gtk_Cell_Renderer_Text;
      Pixbuf_Rend : Gtk_Cell_Renderer_Pixbuf;
      Bar_Render  : Gtk_Cell_Renderer_Progress;
      Dummy       : Gint;
      Cont_N_Inst : constant Context_And_Instance :=
                      (Context => No_Context, Instance => Instance);
      pragma Unreferenced (Dummy);
   begin
      Property.View := new Code_Analysis_View_Record;
      Initialize_Vbox (Property.View, False, 7);
      Property.View.Projects := Property.Projects;
      Gtk_New (Property.View.Model, GType_Array'
          (Pix_Col     => Gdk.Pixbuf.Get_Type,
           Name_Col    => GType_String,
           Node_Col    => GType_Pointer,
           File_Col    => GType_Pointer,
           Prj_Col     => GType_Pointer,
           Cov_Col     => GType_String,
           Cov_Sort    => GType_Int,
           Cov_Bar_Txt => GType_String,
           Cov_Bar_Val => GType_Int));
      Gtk_New (Property.View.Tree, Gtk_Tree_Model (Property.View.Model));
      Set_Name (Property.View.Tree, Property.Instance_Name.all); --  testsuite

      if Is_Error then
         declare
            Warning_Image    : Gtk_Image;
            Error_Label      : Gtk_Label;
            Label_And_Button : Gtk_Vbox;
            Button_Box       : Gtk_Hbox;
            Load_Data_Button : Gtk_Button;
         begin
            Gtk_New_Hbox (Property.View.Error_Box, False, 7);
            Gtk_New_Vbox (Label_And_Button, False, 7);
            Gtk_New_Hbox (Button_Box);
            Gtk_New_From_Icon_Name
              (Warning_Image, Stock_Dialog_Warning, Icon_Size_Dialog);
            Gtk_New
              (Error_Label,
               -"This analysis report is empty. You can populate it with the "
               & '"' & (-"Load data..." & '"' &
                 (-" entries of the /Tools/Coverage menu or the button below."
                   )));
            Set_Line_Wrap (Error_Label, True);
            Set_Justify (Error_Label, Justify_Left);
            Gtk_New (Load_Data_Button, -"Load data for all projects");
            Context_And_Instance_CB.Connect
              (Load_Data_Button, Gtk.Button.Signal_Clicked,
               Context_And_Instance_CB.To_Marshaller
                 (Add_All_Gcov_Project_Info_From_Context'Access),
               Context_And_Instance'
                 (Check_Context (No_Context), Cont_N_Inst.Instance));
            Pack_Start
              (Property.View.Error_Box, Warning_Image, False, False, 7);
            Pack_Start (Label_And_Button, Error_Label, False, True, 7);
            Pack_Start (Button_Box, Load_Data_Button, False, False, 0);
            Pack_Start (Label_And_Button, Button_Box, False, True, 0);
            Pack_Start
              (Property.View.Error_Box, Label_And_Button, False, True, 0);
            Pack_Start
              (Property.View, Property.View.Error_Box, False, True, 0);
         end;
      end if;

      -----------------
      -- Node column --
      -----------------

      Gtk_New (Property.View.Node_Column);
      Gtk_New (Pixbuf_Rend);
      Pack_Start (Property.View.Node_Column, Pixbuf_Rend, False);
      Add_Attribute
        (Property.View.Node_Column, Pixbuf_Rend, "pixbuf", Pix_Col);
      Gtk_New (Text_Render);
      Pack_Start (Property.View.Node_Column, Text_Render, False);
      Add_Attribute
        (Property.View.Node_Column, Text_Render, "text", Name_Col);
      Dummy := Append_Column
        (Property.View.Tree, Property.View.Node_Column);
      Set_Title (Property.View.Node_Column, -"Entities");
      Set_Resizable (Property.View.Node_Column, True);
      Set_Sort_Column_Id (Property.View.Node_Column, Name_Col);

      ----------------------
      -- Coverage columns --
      ----------------------

      Gtk_New (Property.View.Cov_Column);
      Dummy :=
        Append_Column (Property.View.Tree, Property.View.Cov_Column);
      Gtk_New (Text_Render);
      Pack_Start (Property.View.Cov_Column, Text_Render, False);
      Add_Attribute
        (Property.View.Cov_Column, Text_Render, "text", Cov_Col);
      Set_Title (Property.View.Cov_Column, -"Coverage");
      Set_Sort_Column_Id (Property.View.Cov_Column, Cov_Sort);
      Gtk_New (Property.View.Cov_Percent);
      Dummy :=
        Append_Column (Property.View.Tree, Property.View.Cov_Percent);
      Gtk_New (Bar_Render);
      Glib.Properties.Set_Property
        (Bar_Render,
         Gtk.Cell_Renderer.Width_Property,
         Progress_Bar_Width_Cst);
      Pack_Start (Property.View.Cov_Percent, Bar_Render, False);
      Add_Attribute
        (Property.View.Cov_Percent, Bar_Render, "text", Cov_Bar_Txt);
      Add_Attribute
        (Property.View.Cov_Percent, Bar_Render, "value", Cov_Bar_Val);
      Set_Title (Property.View.Cov_Percent, -"Coverage Percentage");
      Set_Sort_Column_Id (Property.View.Cov_Percent, Cov_Bar_Val);
      Gtk_New (Scrolled);
      Set_Policy
        (Scrolled, Gtk.Enums.Policy_Automatic, Gtk.Enums.Policy_Automatic);
      Add (Scrolled, Property.View.Tree);
      Add (Property.View, Scrolled);

      ---------------
      -- MDI child --
      ---------------

      GPS.Kernel.MDI.Gtk_New
        (Property.Child, Property.View,
         Group  => Group_VCS_Explorer,
         Module => Code_Analysis_Module_ID);
      Set_Title
        (Property.Child, -"Report of " & Property.Instance_Name.all);
      Register_Contextual_Menu
        (Code_Analysis_Module_ID.Kernel,
         Event_On_Widget => Property.View.Tree,
         Object          => Property.View,
         ID              => Module_ID (Code_Analysis_Module_ID),
         Context_Func    => Context_Func'Access);
      Gtkada.Handlers.Return_Callback.Object_Connect
        (Property.View.Tree,
         Signal_Button_Press_Event,
         Gtkada.Handlers.Return_Callback.To_Marshaller
           (On_Double_Click'Access),
         Property.View,
         After => False);
      Context_And_Instance_CB.Connect
        (Property.View, Signal_Destroy, Context_And_Instance_CB.To_Marshaller
           (On_Destroy'Access), Cont_N_Inst);
      Put (Get_MDI (Code_Analysis_Module_ID.Kernel), Property.Child);
      GPS.Kernel.Scripts.Set_Property
        (Instance, Code_Analysis_Cst_Str, Instance_Property_Record (Property));
   end Build_Analysis_Report;

   ------------------------
   -- Destroy_From_Shell --
   ------------------------

   procedure Destroy_From_Shell
     (Data    : in out Callback_Data'Class;
      Command : String)
   is
      pragma Unreferenced (Command);
      Instance : constant Class_Instance := Nth_Arg
        (Data, 1, Code_Analysis_Module_ID.Class);
   begin
      if not Is_In_Destruction (Code_Analysis_Module_ID.Kernel) then
         Destroy_Instance (Instance);
      end if;
   exception
      when E : others => Trace (Exception_Handle, E);
   end Destroy_From_Shell;

   -----------------------
   -- Destroy_From_Menu --
   -----------------------

   procedure Destroy_From_Menu
     (Widget      : access Glib.Object.GObject_Record'Class;
      Cont_N_Inst : Context_And_Instance)
   is
      pragma Unreferenced (Widget);
      Property : constant Code_Analysis_Property_Record :=
        Code_Analysis_Property_Record
          (Get_Property (Cont_N_Inst.Instance, Code_Analysis_Cst_Str));
   begin
      if Message_Dialog
        ((-"Destroy ") & Property.Instance_Name.all & (-"?"),
         Confirmation, Button_Yes or Button_No, Justification => Justify_Left,
         Title => Property.Instance_Name.all & (-" destruction?")) = 1
      then
         Destroy_Instance (Cont_N_Inst.Instance);
      end if;
   exception
      when E : others => Trace (Exception_Handle, E);
   end Destroy_From_Menu;

   -------------------------------------
   -- Destroy_All_Instances_From_Menu --
   -------------------------------------

   procedure Destroy_All_Instances_From_Menu
     (Widget : access Gtk.Widget.Gtk_Widget_Record'Class)
   is
      pragma Unreferenced (Widget);
      Analysis_Nb : constant Integer := Integer
        (Code_Analysis_Module_ID.Instances.Length);
   begin
      if Message_Dialog
        ((-"Destroy") & Integer'Image (Analysis_Nb) & (-" analysis?"),
         Confirmation, Button_Yes or Button_No, Justification => Justify_Left,
         Title => Integer'Image (Analysis_Nb) & (-" destructions?")) = 1
      then
         Destroy_All_Instances;
      end if;
   exception
      when E : others => Trace (Exception_Handle, E);
   end Destroy_All_Instances_From_Menu;

   ------------------------------------------------------
   -- Destroy_All_Instances_From_Project_Changing_Hook --
   ------------------------------------------------------

   procedure Destroy_All_Instances_From_Project_Changing_Hook
     (Kernel : access Kernel_Handle_Record'Class;
      Data   : access Hooks_Data'Class)
   is
      pragma Unreferenced (Kernel, Data);
   begin
      Destroy_All_Instances;
   exception
      when E : others => Trace (Exception_Handle, E);
   end Destroy_All_Instances_From_Project_Changing_Hook;

   ---------------------------
   -- Destroy_All_Instances --
   ---------------------------

   procedure Destroy_All_Instances is
      use Code_Analysis_Class_Instance_Sets;
      Cur         : Cursor := Code_Analysis_Module_ID.Instances.First;
      Instance    : Class_Instance;
   begin
      loop
         exit when Cur = No_Element;
         Instance := Element (Cur);
         Next (Cur);
         Destroy_Instance (Instance);
      end loop;
   end Destroy_All_Instances;

   ----------------------
   -- Destroy_Instance --
   ----------------------

   procedure Destroy_Instance (Instance : Class_Instance) is
      Property : Code_Analysis_Property_Record := Code_Analysis_Property_Record
        (Get_Property (Instance, Code_Analysis_Cst_Str));
   begin
      if Property.View /= null then
         Close_Child (Property.Child, Force => True);
      end if;

      Remove_Location_Category
        (Code_Analysis_Module_ID.Kernel, Coverage_Category);
      Remove_Line_Information_Column
        (Code_Analysis_Module_ID.Kernel, No_File, Line_Icons_Cst);
      Remove_Line_Information_Column
        (Code_Analysis_Module_ID.Kernel, No_File, Line_Info_Cst);
      Free_Code_Analysis (Property.Projects);

      if Code_Analysis_Module_ID.Instances.Contains (Instance) then
         Code_Analysis_Module_ID.Instances.Delete (Instance);
      end if;

      GNAT.Strings.Free (Property.Instance_Name);
   end Destroy_Instance;

   ----------------
   -- On_Destroy --
   ----------------

   procedure On_Destroy
     (Widget      : access Glib.Object.GObject_Record'Class;
      Cont_N_Inst : Context_And_Instance)
   is
      pragma Unreferenced (Widget);
      Property : Code_Analysis_Property_Record := Code_Analysis_Property_Record
        (Get_Property (Cont_N_Inst.Instance, Code_Analysis_Cst_Str));
   begin
      Property.View := null;
      GPS.Kernel.Scripts.Set_Property
        (Cont_N_Inst.Instance, Code_Analysis_Cst_Str,
         Instance_Property_Record (Property));
   exception
      when E : others => Trace (Exception_Handle, E);
   end On_Destroy;

   ---------------------
   -- On_Double_Click --
   ---------------------

   function On_Double_Click
     (View  : access Gtk_Widget_Record'Class;
      Event : Gdk_Event) return Boolean
   is
      use Code_Analysis_Tree_Model.File_Set;
      V     : constant Code_Analysis_View := Code_Analysis_View (View);
      Iter  : Gtk_Tree_Iter;
      Model : Gtk_Tree_Model;
   begin
      if Get_Button (Event) = 1
        and then Get_Event_Type (Event) = Gdk_2button_Press
      then
         Get_Selected (Get_Selection (V.Tree), Model, Iter);

         declare
            Node : constant Node_Access := Code_Analysis.Node_Access
              (Node_Set.Get (Gtk_Tree_Store (Model), Iter, Node_Col));
         begin
            if Node.all in Code_Analysis.Project'Class then
               --  So we are on a project node
               null;
            elsif Node.all in Code_Analysis.File'Class then
               --  So we are on a file node
               Open_File_Editor_On_File (Model, Iter);
            elsif Node.all in Code_Analysis.Subprogram'Class then
               --  So we are on a subprogram node
               Open_File_Editor_On_Subprogram (Model, Iter);
            end if;
         end;

         return True;
      end if;

      return False;
   exception
      when E : others => Trace (Exception_Handle, E);
         return False;
   end On_Double_Click;

   ------------------------------
   -- Open_File_Editor_On_File --
   ------------------------------

   procedure Open_File_Editor_On_File
     (Model : Gtk_Tree_Model; Iter : Gtk_Tree_Iter)
   is
      File_Node : constant File_Access := File_Access
        (File_Set.Get (Gtk_Tree_Store (Model), Iter, Node_Col));
   begin
      Open_File_Editor
        (Code_Analysis_Module_ID.Kernel, File_Node.Name);
   end Open_File_Editor_On_File;

   ------------------------------------
   -- Open_File_Editor_On_Subprogram --
   ------------------------------------

   procedure Open_File_Editor_On_Subprogram
     (Model : Gtk_Tree_Model; Iter : Gtk_Tree_Iter)
   is
      File_Node : constant File_Access := File_Access
        (File_Set.Get (Gtk_Tree_Store (Model), Iter, File_Col));
      Subp_Node : constant Subprogram_Access := Subprogram_Access
        (Subprogram_Set.Get (Gtk_Tree_Store (Model), Iter, Node_Col));
   begin
      Open_File_Editor
        (Code_Analysis_Module_ID.Kernel,
         File_Node.Name,
         Subp_Node.Line,
         Basic_Types.Visible_Column_Type (Subp_Node.Column));
   end Open_File_Editor_On_Subprogram;

   -------------------------------------------
   -- Add_Coverage_Annotations_From_Context --
   -------------------------------------------

   procedure Add_Coverage_Annotations_From_Context
     (Widget      : access Glib.Object.GObject_Record'Class;
      Cont_N_Inst : Context_And_Instance)
   is
      pragma Unreferenced (Widget);
      Project_Node : Project_Access;
      File_Node    : Code_Analysis.File_Access;
      Property     : constant Code_Analysis_Property_Record
        := Code_Analysis_Property_Record
          (Get_Property (Cont_N_Inst.Instance, Code_Analysis_Cst_Str));
   begin
      Project_Node := Get_Or_Create
        (Property.Projects, Project_Information (Cont_N_Inst.Context));
      File_Node := Get_Or_Create
        (Project_Node, File_Information (Cont_N_Inst.Context));
      Open_File_Editor (Code_Analysis_Module_ID.Kernel, File_Node.Name);
      Add_Coverage_Annotations (File_Node);
   exception
      when E : others => Trace (Exception_Handle, E);
   end Add_Coverage_Annotations_From_Context;

   ------------------------------
   -- Add_Coverage_Annotations --
   ------------------------------

   procedure Add_Coverage_Annotations
     (File_Node : Code_Analysis.File_Access)
   is
      Line_Info  : Line_Information_Data;
      Line_Icons : Line_Information_Data;
   begin
      Line_Info  := new Line_Information_Array (File_Node.Lines'Range);
      Line_Icons := new Line_Information_Array (File_Node.Lines'Range);

      for J in File_Node.Lines'Range loop
         if File_Node.Lines (J) /= Null_Line then
            Line_Info (J).Text := Line_Coverage_Info
              (File_Node.Lines (J).Analysis_Data.Coverage_Data,
               Binary_Coverage_Mode);

            if File_Node.Lines (J).Analysis_Data.Coverage_Data.Coverage
              = 0 then
               Line_Icons (J).Image := Code_Analysis_Module_ID.Warn_Pixbuf;
            end if;
         end if;
      end loop;

      Create_Line_Information_Column
        (Code_Analysis_Module_ID.Kernel,
         File_Node.Name, Line_Icons_Cst);
      Add_Line_Information
        (Code_Analysis_Module_ID.Kernel,
         File_Node.Name, Line_Icons_Cst,
         Line_Icons);
      Create_Line_Information_Column
        (Code_Analysis_Module_ID.Kernel,
         File_Node.Name, Line_Info_Cst);
      Add_Line_Information
        (Code_Analysis_Module_ID.Kernel,
         File_Node.Name, Line_Info_Cst,
         Line_Info);
      Unchecked_Free (Line_Info);
      Unchecked_Free (Line_Icons);
   end Add_Coverage_Annotations;

   ----------------------------------------------
   -- Remove_Coverage_Annotations_From_Context --
   ----------------------------------------------

   procedure Remove_Coverage_Annotations_From_Context
     (Widget      : access Glib.Object.GObject_Record'Class;
      Cont_N_Inst : Context_And_Instance)
   is
      pragma Unreferenced (Widget);
      Project_Node : Project_Access;
      File_Node    : Code_Analysis.File_Access;
      Property     : constant Code_Analysis_Property_Record
        := Code_Analysis_Property_Record
          (Get_Property (Cont_N_Inst.Instance, Code_Analysis_Cst_Str));
   begin
      Project_Node := Get_Or_Create
        (Property.Projects, Project_Information (Cont_N_Inst.Context));
      File_Node := Get_Or_Create
        (Project_Node, File_Information (Cont_N_Inst.Context));
      Open_File_Editor (Code_Analysis_Module_ID.Kernel, File_Node.Name);
      Remove_Coverage_Annotations (File_Node);
   exception
      when E : others => Trace (Exception_Handle, E);
   end Remove_Coverage_Annotations_From_Context;

   ---------------------------------
   -- Remove_Coverage_Annotations --
   ---------------------------------

   procedure Remove_Coverage_Annotations
     (File_Node : Code_Analysis.File_Access) is
   begin
      Remove_Line_Information_Column
        (Code_Analysis_Module_ID.Kernel, File_Node.Name, Line_Icons_Cst);
      Remove_Line_Information_Column
        (Code_Analysis_Module_ID.Kernel, File_Node.Name, Line_Info_Cst);
   exception
      when E : others => Trace (Exception_Handle, E);
   end Remove_Coverage_Annotations;

   ----------------------------------------------------
   -- List_Lines_Not_Covered_In_Project_From_Context --
   ----------------------------------------------------

   procedure List_Lines_Not_Covered_In_Project_From_Context
     (Widget      : access Glib.Object.GObject_Record'Class;
      Cont_N_Inst : Context_And_Instance)
   is
      pragma Unreferenced (Widget);
      Project_Node : Project_Access;
      Property     : constant Code_Analysis_Property_Record
        := Code_Analysis_Property_Record
          (Get_Property (Cont_N_Inst.Instance, Code_Analysis_Cst_Str));
   begin
      Project_Node := Get_Or_Create
        (Property.Projects, Project_Information (Cont_N_Inst.Context));
      List_Lines_Not_Covered_In_Project (Project_Node);
   exception
      when E : others => Trace (Exception_Handle, E);
   end List_Lines_Not_Covered_In_Project_From_Context;

   -------------------------------------------------
   -- List_Lines_Not_Covered_In_File_From_Context --
   -------------------------------------------------

   procedure List_Lines_Not_Covered_In_File_From_Context
     (Widget      : access Glib.Object.GObject_Record'Class;
      Cont_N_Inst : Context_And_Instance)
   is
      pragma Unreferenced (Widget);
      Property  : constant Code_Analysis_Property_Record
        := Code_Analysis_Property_Record
          (Get_Property (Cont_N_Inst.Instance, Code_Analysis_Cst_Str));
      Prj_Node  : constant Project_Access := Get_Or_Create
        (Property.Projects, Project_Information (Cont_N_Inst.Context));
      File_Node : constant Code_Analysis.File_Access := Get_Or_Create
        (Prj_Node, File_Information (Cont_N_Inst.Context));
   begin
      Open_File_Editor (Code_Analysis_Module_ID.Kernel, File_Node.Name);
      List_Lines_Not_Covered_In_File (File_Node);
   exception
      when E : others => Trace (Exception_Handle, E);
   end List_Lines_Not_Covered_In_File_From_Context;

   ---------------------------------------
   -- List_Lines_Not_Covered_In_Project --
   ---------------------------------------

   procedure List_Lines_Not_Covered_In_Project
     (Project_Node : Project_Access)
   is
      use File_Maps;
      Map_Cur  : File_Maps.Cursor := Project_Node.Files.First;
      Sort_Arr : Code_Analysis.File_Array
        (1 .. Integer (Project_Node.Files.Length));
   begin
      for J in Sort_Arr'Range loop
         Sort_Arr (J) := Element (Map_Cur);
         Next (Map_Cur);
      end loop;

      Sort_Files (Sort_Arr);

      for J in Sort_Arr'Range loop
         if Sort_Arr (J).Analysis_Data.Coverage_Data /= null then
            List_Lines_Not_Covered_In_File (Sort_Arr (J));
         end if;
      end loop;
   end List_Lines_Not_Covered_In_Project;

   ------------------------------------
   -- List_Lines_Not_Covered_In_File --
   ------------------------------------

   procedure List_Lines_Not_Covered_In_File
     (File_Node : Code_Analysis.File_Access)
   is
      No_File_Added : Boolean := True;
   begin
      if File_Node.Analysis_Data.Coverage_Data.Status = Valid then
         for J in File_Node.Lines'Range loop
            if File_Node.Lines (J) /= Null_Line then
               if File_Node.Lines (J).Analysis_Data.Coverage_Data.Coverage
                 = 0 then
                  No_File_Added := False;
                  Insert_Location
                    (Kernel             => Code_Analysis_Module_ID.Kernel,
                     Category           => Coverage_Category,
                     File               => File_Node.Name,
                     Text               => File_Node.Lines (J).Contents.all,
                     Line               => J,
                     Column             => 1,
                     Highlight          => True,
                     Highlight_Category => Builder_Warnings_Style);
               end if;
            end if;
         end loop;

         if No_File_Added then
            GPS.Kernel.Console.Insert
              (Code_Analysis_Module_ID.Kernel,
               -"There is no uncovered line in " &
               Base_Name (File_Node.Name));
         end if;
      else
         GPS.Kernel.Console.Insert
           (Code_Analysis_Module_ID.Kernel,
            -"There is no Gcov information" &
            (-" associated with " & Base_Name (File_Node.Name)),
            Mode => GPS.Kernel.Console.Error);
      end if;
   end List_Lines_Not_Covered_In_File;

   -------------------------------------------------------
   -- List_Lines_Not_Covered_In_Subprogram_From_Context --
   -------------------------------------------------------

   procedure List_Lines_Not_Covered_In_Subprogram_From_Context
     (Widget      : access Glib.Object.GObject_Record'Class;
      Cont_N_Inst : Context_And_Instance)
   is
      pragma Unreferenced (Widget);
      Property  : constant Code_Analysis_Property_Record
        := Code_Analysis_Property_Record
          (Get_Property (Cont_N_Inst.Instance, Code_Analysis_Cst_Str));
      Prj_Node  : constant Project_Access := Get_Or_Create
        (Property.Projects, Project_Information (Cont_N_Inst.Context));
      File_Node : constant Code_Analysis.File_Access := Get_Or_Create
        (Prj_Node, File_Information (Cont_N_Inst.Context));
      Subp_Node : constant Code_Analysis.Subprogram_Access := Get_Or_Create
        (File_Node, new String'(Entity_Name_Information
         (Cont_N_Inst.Context)));
   begin
      if File_Node.Analysis_Data.Coverage_Data.Status = Valid then
         for J in Subp_Node.Start .. Subp_Node.Stop loop
            if File_Node.Lines (J) /= Null_Line then
               if File_Node.Lines (J).Analysis_Data.Coverage_Data.Coverage
                 = 0 then
                  Insert_Location
                    (Kernel             => Code_Analysis_Module_ID.Kernel,
                     Category           => Coverage_Category,
                     File               => File_Node.Name,
                     Text               => File_Node.Lines (J).Contents.all,
                     Line               => J,
                     Column             => 1,
                     Highlight          => True,
                     Highlight_Category => Builder_Warnings_Style);
               end if;
            end if;
         end loop;
      else
         GPS.Kernel.Console.Insert
           (Code_Analysis_Module_ID.Kernel,
            -"There is no Gcov information" &
            (-" associated with " & Base_Name (File_Node.Name)),
            Mode => GPS.Kernel.Console.Error);
      end if;
   exception
      when E : others => Trace (Exception_Handle, E);
   end List_Lines_Not_Covered_In_Subprogram_From_Context;

   ---------------------------------
   -- Remove_Subprogram_From_Menu --
   ---------------------------------

   procedure Remove_Subprogram_From_Menu
      (Widget      : access Glib.Object.GObject_Record'Class;
       Cont_N_Inst : Context_And_Instance)
   is
      pragma Unreferenced (Widget);
      Property  : Code_Analysis_Property_Record
        := Code_Analysis_Property_Record
          (Get_Property (Cont_N_Inst.Instance, Code_Analysis_Cst_Str));
      Prj_Node  : constant Project_Access := Get_Or_Create
        (Property.Projects, Project_Information (Cont_N_Inst.Context));
      File_Node : constant Code_Analysis.File_Access := Get_Or_Create
        (Prj_Node, File_Information (Cont_N_Inst.Context));
      Subp_Node : Code_Analysis.Subprogram_Access := Get_Or_Create
        (File_Node, new String'(Entity_Name_Information
         (Cont_N_Inst.Context)));
      Prj_Iter   : Gtk_Tree_Iter;
      File_Iter  : Gtk_Tree_Iter;
      Subp_Iter  : Gtk_Tree_Iter;
   begin
      if Message_Dialog
        ((-"Remove data of ") & Subp_Node.Name.all & (-"?"),
         Confirmation, Button_Yes or Button_No,
         Justification => Justify_Left,
         Title         => (-"Remove ") & Subp_Node.Name.all & (-"?")) = 1
      then
         if Property.View = null then
            Show_Analysis_Report (Cont_N_Inst, Property, False);
         end if;

         --  Update project coverage information
         Prj_Node.Analysis_Data.Coverage_Data.Coverage :=
           Prj_Node.Analysis_Data.Coverage_Data.Coverage -
             Subp_Node.Analysis_Data.Coverage_Data.Coverage;
         Subprogram_Coverage
           (Prj_Node.Analysis_Data.Coverage_Data.all).Children :=
           Subprogram_Coverage
             (Prj_Node.Analysis_Data.Coverage_Data.all).Children -
             Subprogram_Coverage
               (Subp_Node.Analysis_Data.Coverage_Data.all).Children;
         --  Update file coverage information
         File_Node.Analysis_Data.Coverage_Data.Coverage :=
           File_Node.Analysis_Data.Coverage_Data.Coverage -
             Subp_Node.Analysis_Data.Coverage_Data.Coverage;
         Node_Coverage (File_Node.Analysis_Data.Coverage_Data.all).Children :=
           Node_Coverage (File_Node.Analysis_Data.Coverage_Data.all).Children -
           Subprogram_Coverage
             (Subp_Node.Analysis_Data.Coverage_Data.all).Children;
         Subp_Iter := Get_Iter_From_Context
           (Cont_N_Inst.Context, Property.View.Model);
         File_Iter := Parent (Property.View.Model, Subp_Iter);
         Fill_Iter (Property.View.Model, File_Iter, File_Node.Analysis_Data,
                    Binary_Coverage_Mode);
         Prj_Iter  := Parent (Property.View.Model, File_Iter);
         Fill_Iter (Property.View.Model, Prj_Iter, Prj_Node.Analysis_Data,
                    Binary_Coverage_Mode);
         --  Removes Subp_Iter from the report
         Remove (Property.View.Model, Subp_Iter);
         --  Removes Subp_Iter from its container
         Subprogram_Maps.Delete (File_Node.Subprograms, Subp_Node.Name.all);
         --  Free Subprogram analysis node
         Free_Subprogram (Subp_Node);
      end if;
   exception
      when E : others => Trace (Exception_Handle, E);
   end Remove_Subprogram_From_Menu;

   ---------------------------
   -- Remove_File_From_Menu --
   ---------------------------

   procedure Remove_File_From_Menu
     (Widget      : access Glib.Object.GObject_Record'Class;
      Cont_N_Inst : Context_And_Instance)
   is
      pragma Unreferenced (Widget);
      Property  : Code_Analysis_Property_Record
        := Code_Analysis_Property_Record
          (Get_Property (Cont_N_Inst.Instance, Code_Analysis_Cst_Str));
      Prj_Node  : constant Project_Access := Get_Or_Create
        (Property.Projects, Project_Information (Cont_N_Inst.Context));
      File_Node : Code_Analysis.File_Access := Get_Or_Create
        (Prj_Node, File_Information (Cont_N_Inst.Context));
      File_Iter : Gtk_Tree_Iter;
      Prj_Iter  : Gtk_Tree_Iter;
   begin
      if Message_Dialog
        ((-"Remove data of ") & Base_Name (File_Node.Name) & (-"?"),
         Confirmation, Button_Yes or Button_No,
         Justification => Justify_Left,
         Title         => (-"Remove ") & Base_Name (File_Node.Name) & (-"?"))
        = 1
      then
         if Property.View = null then
            Show_Analysis_Report (Cont_N_Inst, Property, False);
         end if;

         --  Update project coverage information
         Prj_Node.Analysis_Data.Coverage_Data.Coverage :=
           Prj_Node.Analysis_Data.Coverage_Data.Coverage -
             File_Node.Analysis_Data.Coverage_Data.Coverage;
         Subprogram_Coverage
           (Prj_Node.Analysis_Data.Coverage_Data.all).Children :=
           Subprogram_Coverage
             (Prj_Node.Analysis_Data.Coverage_Data.all).Children -
             Node_Coverage
               (File_Node.Analysis_Data.Coverage_Data.all).Children;
         File_Iter := Get_Iter_From_Context
           (Cont_N_Inst.Context, Property.View.Model);
         Prj_Iter  := Parent (Property.View.Model, File_Iter);
         Fill_Iter (Property.View.Model, Prj_Iter, Prj_Node.Analysis_Data,
                    Binary_Coverage_Mode);
         --  Removes File_Iter from the report
         Remove (Property.View.Model, File_Iter);
         --  Removes File_Iter from its container
         File_Maps.Delete (Prj_Node.Files, File_Node.Name);
         --  Free the file analysis node
         Free_File (File_Node);
      end if;
   exception
      when E : others => Trace (Exception_Handle, E);
   end Remove_File_From_Menu;

   ------------------------------
   -- Remove_Project_From_Menu --
   ------------------------------

   procedure Remove_Project_From_Menu
      (Widget      : access Glib.Object.GObject_Record'Class;
      Cont_N_Inst : Context_And_Instance)
   is
      pragma Unreferenced (Widget);
      Property : Code_Analysis_Property_Record
        := Code_Analysis_Property_Record
          (Get_Property (Cont_N_Inst.Instance, Code_Analysis_Cst_Str));
      Prj_Node : Project_Access := Get_Or_Create
        (Property.Projects, Project_Information (Cont_N_Inst.Context));
      Iter     : Gtk_Tree_Iter;
   begin
      if Message_Dialog
        ((-"Remove data of project ") & Project_Name (Prj_Node.Name) & (-"?"),
         Confirmation, Button_Yes or Button_No,
         Justification => Justify_Left,
         Title         => (-"Remove ") & Project_Name (Prj_Node.Name) & (-"?"))
        = 1
      then
         if Property.View = null then
            Show_Analysis_Report (Cont_N_Inst, Property, False);
         end if;

         Iter := Get_Iter_From_Context
           (Cont_N_Inst.Context, Property.View.Model);
         --  Removes it from the report
         Remove (Property.View.Model, Iter);
         --  Removes it from its container
         Project_Maps.Delete (Property.Projects.all, Prj_Node.Name);
         --  Free it
         Free_Project (Prj_Node);
      end if;
   exception
      when E : others => Trace (Exception_Handle, E);
   end Remove_Project_From_Menu;

   ----------------------------
   -- Expand_All_From_Report --
   ----------------------------

   procedure Expand_All_From_Report (Object : access Gtk_Widget_Record'Class)
   is
      View : constant Code_Analysis_View := Code_Analysis_View (Object);
   begin
      Expand_All (View.Tree);
   exception
      when E : others => Trace (Exception_Handle, E);
   end Expand_All_From_Report;

   ------------------------------
   -- Collapse_All_From_Report --
   ------------------------------

   procedure Collapse_All_From_Report (Object : access Gtk_Widget_Record'Class)
   is
      View : constant Code_Analysis_View := Code_Analysis_View (Object);
   begin
      Collapse_All (View.Tree);
   exception
      when E : others => Trace (Exception_Handle, E);
   end Collapse_All_From_Report;

   --------------------
   -- Show_Full_Tree --
   --------------------

   procedure Show_Full_Tree (Object : access Gtk_Widget_Record'Class) is
      View : constant Code_Analysis_View := Code_Analysis_View (Object);
      Iter : Gtk_Tree_Iter := Get_Iter_First (View.Model);
      Path : Gtk_Tree_Path;
   begin
      Clear (View.Model);
      Fill_Iter (View.Model, Iter, View.Projects, Binary_Coverage_Mode);
      Iter := Get_Iter_First (View.Model);
      Path := Get_Path (View.Model, Iter);
      Collapse_All (View.Tree);
      Expand_To_Path (View.Tree, Path);
      Select_Path (Get_Selection (View.Tree), Path);
      Path_Free (Path);
   exception
      when E : others => Trace (Exception_Handle, E);
   end Show_Full_Tree;

   -----------------------------
   -- Show_Flat_List_Of_Files --
   -----------------------------

   procedure Show_Flat_List_Of_Files (Object : access Gtk_Widget_Record'Class)
   is
      View : constant Code_Analysis_View := Code_Analysis_View (Object);
      Iter : Gtk_Tree_Iter := Get_Iter_First (View.Model);
   begin
      Clear (View.Model);
      Fill_Iter_With_Files (View.Model, Iter, View.Projects,
                            Binary_Coverage_Mode);
   exception
      when E : others => Trace (Exception_Handle, E);
   end Show_Flat_List_Of_Files;

   -----------------------------------
   -- Show_Flat_List_Of_Subprograms --
   -----------------------------------

   procedure Show_Flat_List_Of_Subprograms
     (Object : access Gtk_Widget_Record'Class)
   is
      View : constant Code_Analysis_View := Code_Analysis_View (Object);
      Iter : Gtk_Tree_Iter := Get_Iter_First (View.Model);
   begin
      Clear (View.Model);
      Fill_Iter_With_Subprograms (View.Model, Iter, View.Projects,
                                  Binary_Coverage_Mode);
   exception
      when E : others => Trace (Exception_Handle, E);
   end Show_Flat_List_Of_Subprograms;

   -----------------------------
   -- Contextual menu entries --
   -----------------------------

   ------------------
   -- Context_Func --
   ------------------

   procedure Context_Func
     (Context      : in out Selection_Context;
      Kernel       : access Kernel_Handle_Record'Class;
      Event_Widget : access Gtk.Widget.Gtk_Widget_Record'Class;
      Object       : access Glib.Object.GObject_Record'Class;
      Event        : Gdk_Event;
      Menu         : Gtk_Menu)
   is
      pragma Unreferenced (Kernel, Event_Widget);
      View      : constant Code_Analysis_View := Code_Analysis_View (Object);
      X         : constant Gdouble := Get_X (Event);
      Y         : constant Gdouble := Get_Y (Event);
      Path      : Gtk_Tree_Path;
      Prj_Node  : Code_Analysis.Project_Access;
      File_Node : Code_Analysis.File_Access;
      Column    : Gtk_Tree_View_Column;
      Buffer_X  : Gint;
      Buffer_Y  : Gint;
      Row_Found : Boolean;
      Item      : Gtk_Menu_Item;
      Iter      : Gtk_Tree_Iter := Get_Iter_First (View.Model);
   begin

      Get_Path_At_Pos (View.Tree, Gint (X), Gint (Y), Path, Column,
                       Buffer_X, Buffer_Y, Row_Found);

      ---------------------------------------------------------------
      --  Insert Report of Analysis # specific contextual entries  --
      ---------------------------------------------------------------

      Gtk_New (Item, -"Show flat list of files");
      Gtkada.Handlers.Widget_Callback.Object_Connect
        (Item, Gtk.Menu_Item.Signal_Activate,
         Show_Flat_List_Of_Files'Access, View);
      Append (Menu, Item);
      Gtk_New (Item, -"Show flat list of subprograms");
      Gtkada.Handlers.Widget_Callback.Object_Connect
        (Item, Gtk.Menu_Item.Signal_Activate,
         Show_Flat_List_Of_Subprograms'Access, View);
      Append (Menu, Item);

      if not Has_Child (View.Model, Iter) then
         Gtk_New (Item, -"Show full tree");
         Gtkada.Handlers.Widget_Callback.Object_Connect
           (Item, Gtk.Menu_Item.Signal_Activate, Show_Full_Tree'Access, View);
         Append (Menu, Item);
      else
         Gtk_New (Item, -"Expand all");
         Gtkada.Handlers.Widget_Callback.Object_Connect
           (Item, Gtk.Menu_Item.Signal_Activate,
            Expand_All_From_Report'Access, View);
         Append (Menu, Item);
         Gtk_New (Item, -"Collapse all");
         Gtkada.Handlers.Widget_Callback.Object_Connect
           (Item, Gtk.Menu_Item.Signal_Activate,
            Collapse_All_From_Report'Access, View);
         Append (Menu, Item);
      end if;

      ----------------------------------
      --  Set up context information  --
      ----------------------------------

      if Path /= null then
         Gtk_New (Item);
         Append (Menu, Item);
         Select_Path (Get_Selection (View.Tree), Path);
         Iter := Get_Iter (Gtk_Tree_Model (View.Model), Path);

         declare
            Node : constant Node_Access := Code_Analysis.Node_Access
              (Node_Set.Get (Gtk_Tree_Store (View.Model), Iter, Node_Col));
         begin
            if Node.all in Code_Analysis.Project'Class then
               --  So we are on a project node
               --  Context receive project information
               Set_File_Information
                 (Context, Project => Project_Access (Node).Name);
            elsif Node.all in Code_Analysis.File'Class then
               --  So we are on a file node
               --  Context receive project and file information
               Prj_Node := Project_Access
                 (Project_Set.Get
                    (Gtk_Tree_Store (View.Model), Iter, Prj_Col));
               Set_File_Information
                 (Context,
                  File    => Code_Analysis.File_Access (Node).Name,
                  Project => Prj_Node.Name);
            elsif Node.all in Code_Analysis.Subprogram'Class then
               --  So we are on a subprogram node
               --  Context receive project, file and entity information
               File_Node := Code_Analysis.File_Access
                 (File_Set.Get (Gtk_Tree_Store (View.Model),
                  Iter, File_Col));
               Prj_Node  := Project_Access
                 (Project_Set.Get (Gtk_Tree_Store (View.Model),
                  Iter, Prj_Col));
               Set_File_Information (Context, File_Node.Name, Prj_Node.Name);
               Set_Entity_Information
                 (Context, Subprogram_Access (Node).Name.all);
            end if;
         end;
      end if;
   end Context_Func;

   ------------------------------
   -- Filter_Matches_Primitive --
   ------------------------------

   function Filter_Matches_Primitive
     (Filter  : access Has_Coverage_Filter;
      Context : Selection_Context) return Boolean
   is
      pragma Unreferenced (Filter);
      Entity : Entity_Information;
   begin
      if Has_Project_Information (Context)
        or else Has_File_Information (Context)
      then
         return True;

      elsif Has_Entity_Name_Information (Context) then
         Entity := Get_Entity (Context);

         return (Entity /= null
                 and then Is_Subprogram (Entity))
           or else Get_Creator (Context) = Abstract_Module_ID
           (Code_Analysis_Module_ID);
      end if;

      return False;
   end Filter_Matches_Primitive;

   --------------------
   -- Append_To_Menu --
   --------------------

   procedure Append_To_Menu
     (Factory : access Code_Analysis_Contextual_Menu;
      Object  : access Glib.Object.GObject_Record'Class;
      Context : Selection_Context;
      Menu    : access Gtk.Menu.Gtk_Menu_Record'Class)
   is
      use Code_Analysis_Class_Instance_Sets;
      pragma Unreferenced (Factory, Object);
      Cont_N_Inst  : Context_And_Instance;
      Property     : Code_Analysis_Property_Record;
      Project_Node : Project_Access;
      Submenu      : Gtk_Menu;
      Item         : Gtk_Menu_Item;
      Cur          : Cursor := Code_Analysis_Module_ID.Instances.First;
   begin
      Cont_N_Inst.Context := Context;

      loop
         exit when Cur = No_Element;

         Cont_N_Inst.Instance := Element (Cur);
         Property             := Code_Analysis_Property_Record
           (Get_Property (Cont_N_Inst.Instance, Code_Analysis_Cst_Str));
         Project_Node         := Get_Or_Create
           (Property.Projects, Project_Information (Cont_N_Inst.Context));

         if Code_Analysis_Module_ID.Instances.Length > 1 then
            Gtk_New (Item, -(Property.Instance_Name.all));
            Append (Menu, Item);
            Gtk_New (Submenu);
            Set_Submenu (Item, Submenu);
            Set_Sensitive (Item, True);
            Append_To_Contextual_Submenu (Cont_N_Inst, Submenu, Project_Node);
         else
            Append_To_Contextual_Submenu (Cont_N_Inst, Menu, Project_Node);
         end if;

         Next (Cur);
      end loop;
   end Append_To_Menu;

   ----------------------------------
   -- Append_To_Contextual_Submenu --
   ----------------------------------

   procedure Append_To_Contextual_Submenu
     (Cont_N_Inst  : Context_And_Instance;
      Submenu      : access Gtk_Menu_Record'Class;
      Project_Node : Project_Access)
   is
      Item : Gtk_Menu_Item;
   begin
      if Has_File_Information (Cont_N_Inst.Context) then
         declare
            File_Node : constant Code_Analysis.File_Access := Get_Or_Create
              (Project_Node, File_Information (Cont_N_Inst.Context));
         begin
            if Has_Entity_Name_Information (Cont_N_Inst.Context) then
               declare
                  Entity    : constant Entities.Entity_Information :=
                                Get_Entity (Cont_N_Inst.Context);
                  Subp_Node : Subprogram_Access;
               begin
                  if (Entity /= null
                      and then Is_Subprogram (Entity))
                    or else  Get_Creator (Cont_N_Inst.Context) =
                    Abstract_Module_ID (Code_Analysis_Module_ID)
                  then
                     --  So we have a subprogram information
                     Subp_Node := Get_Or_Create
                       (File_Node, new String'(Entity_Name_Information
                        (Cont_N_Inst.Context)));
                     Append_Subprogram_Menu_Entries
                       (Cont_N_Inst, Submenu, Subp_Node);
                  else
                     Append_File_Menu_Entries
                       (Cont_N_Inst, Submenu, File_Node);
                  end if;
               end;
            else
               Append_File_Menu_Entries (Cont_N_Inst, Submenu, File_Node);
            end if;
         end;
      else
         Append_Project_Menu_Entries (Cont_N_Inst, Submenu, Project_Node);
      end if;

      if Get_Creator (Cont_N_Inst.Context) /=
        Abstract_Module_ID (Code_Analysis_Module_ID) then
         Gtk_New (Item);
         Append (Submenu, Item);
         Append_Show_Analysis_Report_To_Menu (Cont_N_Inst, Submenu);
      end if;
   end Append_To_Contextual_Submenu;

   ------------------------------------
   -- Append_Subprogram_Menu_Entries --
   ------------------------------------

   procedure Append_Subprogram_Menu_Entries
     (Cont_N_Inst : Context_And_Instance;
      Submenu     : access Gtk_Menu_Record'Class;
      Subp_Node   : Subprogram_Access)
   is
      Item : Gtk_Menu_Item;
   begin
      if Subp_Node.Analysis_Data.Coverage_Data /= null then
         Gtk_New (Item, -"List lines not covered");
         Append (Submenu, Item);
         Context_And_Instance_CB.Connect
           (Item, Gtk.Menu_Item.Signal_Activate,
            Context_And_Instance_CB.To_Marshaller
              (List_Lines_Not_Covered_In_Subprogram_From_Context'Access),
            Cont_N_Inst);
         Gtk_New (Item, -"Remove data of " & Entity_Name_Information
                  (Cont_N_Inst.Context));
         Append (Submenu, Item);
         Context_And_Instance_CB.Connect
           (Item, Gtk.Menu_Item.Signal_Activate,
            Context_And_Instance_CB.To_Marshaller
              (Remove_Subprogram_From_Menu'Access), Cont_N_Inst);
      else
         Gtk_New (Item, -"Load data for " &
                  Locale_Base_Name (File_Information (Cont_N_Inst.Context)));
         Append (Submenu, Item);
         Context_And_Instance_CB.Connect
           (Item, Gtk.Menu_Item.Signal_Activate,
            Context_And_Instance_CB.To_Marshaller
              (Add_Gcov_File_Info_From_Context'Access), Cont_N_Inst);
      end if;
   end Append_Subprogram_Menu_Entries;

   ------------------------------
   -- Append_File_Menu_Entries --
   ------------------------------

   procedure Append_File_Menu_Entries
     (Cont_N_Inst : Context_And_Instance;
      Submenu     : access Gtk_Menu_Record'Class;
      File_Node   : Code_Analysis.File_Access)
   is
      Item : Gtk_Menu_Item;
   begin
      if File_Node.Analysis_Data.Coverage_Data /= null and then
        File_Node.Analysis_Data.Coverage_Data.Status = Valid then
         Gtk_New (Item, -"Reload data for " &
                  Locale_Base_Name (File_Information (Cont_N_Inst.Context)));
         Append (Submenu, Item);
         Context_And_Instance_CB.Connect
           (Item, Gtk.Menu_Item.Signal_Activate,
            Context_And_Instance_CB.To_Marshaller
              (Add_Gcov_File_Info_From_Context'Access), Cont_N_Inst);
         Gtk_New (Item, -"Add coverage annotations");
         Append (Submenu, Item);
         Context_And_Instance_CB.Connect
           (Item, Gtk.Menu_Item.Signal_Activate,
            Context_And_Instance_CB.To_Marshaller
              (Add_Coverage_Annotations_From_Context'Access), Cont_N_Inst);
         Gtk_New (Item, -"Remove coverage annotations");
         Append (Submenu, Item);
         Context_And_Instance_CB.Connect
           (Item, Gtk.Menu_Item.Signal_Activate,
            Context_And_Instance_CB.To_Marshaller
              (Remove_Coverage_Annotations_From_Context'Access), Cont_N_Inst);
         Gtk_New (Item, -"List lines not covered");
         Append (Submenu, Item);
         Context_And_Instance_CB.Connect
           (Item, Gtk.Menu_Item.Signal_Activate,
            Context_And_Instance_CB.To_Marshaller
              (List_Lines_Not_Covered_In_File_From_Context'Access),
            Cont_N_Inst);
         Gtk_New (Item, -"Remove data of " &
                  Base_Name (File_Information (Cont_N_Inst.Context)));
         Append (Submenu, Item);
         Context_And_Instance_CB.Connect
           (Item, Gtk.Menu_Item.Signal_Activate,
            Context_And_Instance_CB.To_Marshaller
              (Remove_File_From_Menu'Access), Cont_N_Inst);
      else
         Gtk_New (Item, -"Load data for " &
                  Locale_Base_Name (File_Information (Cont_N_Inst.Context)));
         Append (Submenu, Item);
         Context_And_Instance_CB.Connect
           (Item, Gtk.Menu_Item.Signal_Activate,
            Context_And_Instance_CB.To_Marshaller
              (Add_Gcov_File_Info_From_Context'Access), Cont_N_Inst);
      end if;
   end Append_File_Menu_Entries;

   ---------------------------------
   -- Append_Project_Menu_Entries --
   ---------------------------------

   procedure Append_Project_Menu_Entries
     (Cont_N_Inst   : Context_And_Instance;
      Submenu       : access Gtk_Menu_Record'Class;
      Project_Node  : Project_Access)
   is
      Item : Gtk_Menu_Item;
   begin
      if Project_Node.Analysis_Data.Coverage_Data /= null then
         Gtk_New (Item, -"Reload data for project " &
                  Project_Name (Project_Information (Cont_N_Inst.Context)));
         Append (Submenu, Item);
         Context_And_Instance_CB.Connect
           (Item, Gtk.Menu_Item.Signal_Activate,
            Context_And_Instance_CB.To_Marshaller
              (Add_Gcov_Project_Info_From_Context'Access), Cont_N_Inst);
         Gtk_New (Item, -"List lines not covered");
         Append (Submenu, Item);
         Context_And_Instance_CB.Connect
           (Item, Gtk.Menu_Item.Signal_Activate,
            Context_And_Instance_CB.To_Marshaller
              (List_Lines_Not_Covered_In_Project_From_Context'Access),
            Cont_N_Inst);
         Gtk_New (Item, -"Remove data of project " &
                  Project_Name (Project_Information (Cont_N_Inst.Context)));
         Append (Submenu, Item);
         Context_And_Instance_CB.Connect
           (Item, Gtk.Menu_Item.Signal_Activate,
            Context_And_Instance_CB.To_Marshaller
              (Remove_Project_From_Menu'Access), Cont_N_Inst);
      else
         Gtk_New (Item, -"Load data for project " &
                  Project_Name (Project_Information (Cont_N_Inst.Context)));
         Append (Submenu, Item);
         Context_And_Instance_CB.Connect
           (Item, Gtk.Menu_Item.Signal_Activate,
            Context_And_Instance_CB.To_Marshaller
              (Add_Gcov_Project_Info_From_Context'Access), Cont_N_Inst);
      end if;
   end Append_Project_Menu_Entries;

   ------------------
   -- Menu entries --
   ------------------

   -------------------
   -- Check_Context --
   -------------------

   function Check_Context
     (Given_Context : Selection_Context) return Selection_Context
   is
      Checked_Context : Selection_Context;
   begin
      if Given_Context = No_Context then
         Checked_Context := Get_Current_Context
           (Code_Analysis_Module_ID.Kernel);
      else
         Checked_Context := Given_Context;
      end if;

      if not Has_Project_Information (Checked_Context) then
         if Has_File_Information (Checked_Context) then
            declare
               Prj_Info  : Project_Type;
               File_Info : constant VFS.Virtual_File :=
                             File_Information (Checked_Context);
            begin
               Prj_Info := Get_Project_From_File
                 (Get_Registry (Code_Analysis_Module_ID.Kernel).all,
                  File_Info);
               Set_File_Information (Checked_Context, File_Info, Prj_Info);
            end;
         else
            Set_File_Information
              (Checked_Context,
               Project => Get_Project (Code_Analysis_Module_ID.Kernel));
         end if;
      end if;

      return Checked_Context;
   end Check_Context;

   --------------------------------
   -- Dynamic_Tools_Menu_Factory --
   --------------------------------

   procedure Dynamic_Tools_Menu_Factory
     (Kernel  : access Kernel_Handle_Record'Class;
      Context : Selection_Context;
      Menu    : access Gtk.Menu.Gtk_Menu_Record'Class)
   is
      pragma Unreferenced (Kernel);
      use Code_Analysis_Class_Instance_Sets;
      Cont_N_Inst : Context_And_Instance;
      Property    : Code_Analysis_Property_Record;
      Prj_Node    : Project_Access;
      Submenu     : Gtk_Menu;
      Item        : Gtk_Menu_Item;
      Cur         : Cursor := Code_Analysis_Module_ID.Instances.First;
   begin
      Cont_N_Inst.Context := Check_Context (Context);

      if Cur = No_Element then
         Cont_N_Inst.Instance := No_Class_Instance;
         Append_Load_Data_For_All_Projects (Cont_N_Inst, Menu);
         Gtk_New (Item, -"Load data for project " &
                  Project_Name (Project_Information (Cont_N_Inst.Context)));
         Append (Menu, Item);
         Context_And_Instance_CB.Connect
           (Item, Gtk.Menu_Item.Signal_Activate,
            Context_And_Instance_CB.To_Marshaller
              (Add_Gcov_Project_Info_From_Context'Access), Cont_N_Inst);

         if Has_File_Information (Cont_N_Inst.Context) then
            Gtk_New
              (Item, -"Load data for " &
               Locale_Base_Name (File_Information (Cont_N_Inst.Context)));
            Append (Menu, Item);
            Context_And_Instance_CB.Connect
              (Item, Gtk.Menu_Item.Signal_Activate,
               Context_And_Instance_CB.To_Marshaller
                 (Add_Gcov_File_Info_From_Context'Access), Cont_N_Inst);
         end if;

         Gtk_New (Item);
         Append (Menu, Item);
      else
         loop
            exit when Cur = No_Element;
            Cont_N_Inst.Instance := Element (Cur);
            Next (Cur);
            Property             := Code_Analysis_Property_Record
              (Get_Property (Cont_N_Inst.Instance, Code_Analysis_Cst_Str));
            Prj_Node             := Get_Or_Create
              (Property.Projects, Project_Information (Cont_N_Inst.Context));

            if Code_Analysis_Module_ID.Instances.Length > 1 then
               Gtk_New (Item, -(Property.Instance_Name.all));
               Append (Menu, Item);
               Gtk_New (Submenu);
               Set_Submenu (Item, Submenu);
               Set_Sensitive (Item, True);
               Append_To_Submenu (Cont_N_Inst, Submenu, Prj_Node);
            else
               Append_To_Submenu (Cont_N_Inst, Menu, Prj_Node);
               Gtk_New (Item);
               Append (Menu, Item);
            end if;
         end loop;
      end if;

      Gtk_New (Item, -"Create code analysis");
      Append (Menu, Item);
      Gtkada.Handlers.Widget_Callback.Connect
        (Item, Gtk.Menu_Item.Signal_Activate, Create_From_Menu'Access);

      if Code_Analysis_Module_ID.Instances.Length > 1 then
         Gtk_New (Item, -"Remove all analysis");
         Append (Menu, Item);
         Gtkada.Handlers.Widget_Callback.Connect
           (Item, Gtk.Menu_Item.Signal_Activate,
            Destroy_All_Instances_From_Menu'Access);
      end if;
   end Dynamic_Tools_Menu_Factory;

   --------------------------------
   -- Dynamic_Views_Menu_Factory --
   --------------------------------

   procedure Dynamic_Views_Menu_Factory
     (Kernel  : access Kernel_Handle_Record'Class;
      Context : Selection_Context;
      Menu    : access Gtk.Menu.Gtk_Menu_Record'Class)
   is
      pragma Unreferenced (Kernel);
      use Code_Analysis_Class_Instance_Sets;
      Cur      : Cursor := Code_Analysis_Module_ID.Instances.First;
      Item     : Gtk_Menu_Item;
      Instance : Class_Instance;
   begin
      if Cur = No_Element then
         --  So there's currently no instances
         Gtk_New (Item, -"Show Report of Analysis");
         Append (Menu, Item);
         Gtkada.Handlers.Object_Callback.Connect
           (Item, Gtk.Menu_Item.Signal_Activate,
            Show_Empty_Analysis_Report_From_Menu'Access);
         return;
      end if;

      loop
         exit when Cur = No_Element;
         Instance := Element (Cur);
         Append_Show_Analysis_Report_To_Menu
           (Context_And_Instance'(Context, Instance), Menu);
         Next (Cur);
      end loop;
   end Dynamic_Views_Menu_Factory;

   -----------------------
   -- Append_To_Submenu --
   -----------------------

   procedure Append_To_Submenu
     (Cont_N_Inst  : Context_And_Instance;
      Submenu      : access Gtk_Menu_Record'Class;
      Project_Node : Project_Access)
   is
      Item     : Gtk_Menu_Item;
      Property : constant Code_Analysis_Property_Record :=
        Code_Analysis_Property_Record
        (Get_Property (Cont_N_Inst.Instance, Code_Analysis_Cst_Str));
   begin
      Append_Show_Analysis_Report_To_Menu (Cont_N_Inst, Submenu);
      Gtk_New (Item, -"Remove " & Property.Instance_Name.all);
      Append (Submenu, Item);
      Context_And_Instance_CB.Connect
        (Item, Gtk.Menu_Item.Signal_Activate,
         Context_And_Instance_CB.To_Marshaller
           (Destroy_From_Menu'Access), Cont_N_Inst);
      Gtk_New (Item);
      Append (Submenu, Item);
      Append_Load_Data_For_All_Projects (Cont_N_Inst, Submenu);

      if First_Project_With_Coverage_Data (Property) /= No_Project then
         Gtk_New (Item, -"List lines not covered in all projects");
         Append (Submenu, Item);
         Context_And_Instance_CB.Connect
           (Item, Gtk.Menu_Item.Signal_Activate,
            Context_And_Instance_CB.To_Marshaller
              (List_Lines_Not_Covered_In_All_Projects_From_Menu'Access),
            Cont_N_Inst);
      end if;

      Append_Project_Menu_Entries (Cont_N_Inst, Submenu, Project_Node);

      if Has_File_Information (Cont_N_Inst.Context) then
         declare
            File_Node : constant Code_Analysis.File_Access := Get_Or_Create
              (Project_Node, File_Information (Cont_N_Inst.Context));
         begin
            Gtk_New (Item);
            Append (Submenu, Item);
            Append_File_Menu_Entries (Cont_N_Inst, Submenu, File_Node);
         end;
      end if;
   end Append_To_Submenu;

   -----------------------------------------
   -- Append_Show_Analysis_Report_To_Menu --
   -----------------------------------------

   procedure Append_Show_Analysis_Report_To_Menu
     (Cont_N_Inst : Context_And_Instance;
      Menu        : access Gtk_Menu_Record'Class)
   is
      Item     : Gtk_Menu_Item;
      Property : constant Code_Analysis_Property_Record :=
        Code_Analysis_Property_Record
          (Get_Property (Cont_N_Inst.Instance, Code_Analysis_Cst_Str));
   begin
      Gtk_New (Item, -"Show Report of " & Property.Instance_Name.all);
      Append (Menu, Item);
      Context_And_Instance_CB.Connect
        (Item, Gtk.Menu_Item.Signal_Activate,
         Context_And_Instance_CB.To_Marshaller
           (Show_Analysis_Report_From_Menu'Access), Cont_N_Inst);
   end Append_Show_Analysis_Report_To_Menu;

   ---------------------------------------
   -- Append_Load_Data_For_All_Projects --
   ---------------------------------------

   procedure Append_Load_Data_For_All_Projects
     (Cont_N_Inst : Context_And_Instance;
      Menu        : access Gtk_Menu_Record'Class)
   is
      Cont_N_Inst_Root_Prj : Context_And_Instance;
      Item                 : Gtk_Menu_Item;
   begin
      Cont_N_Inst_Root_Prj.Instance := Cont_N_Inst.Instance;
      Cont_N_Inst_Root_Prj.Context  := Get_Current_Context
        (Code_Analysis_Module_ID.Kernel);
      Set_File_Information
        (Cont_N_Inst_Root_Prj.Context,
         Project => Get_Project (Code_Analysis_Module_ID.Kernel));
      Gtk_New (Item, -"Load data for all projects");
      Append (Menu, Item);
      Context_And_Instance_CB.Connect
        (Item, Gtk.Menu_Item.Signal_Activate,
         Context_And_Instance_CB.To_Marshaller
           (Add_All_Gcov_Project_Info_From_Context'Access),
         Cont_N_Inst_Root_Prj);
   end Append_Load_Data_For_All_Projects;

   ---------------------------
   -- Less_Case_Insensitive --
   ---------------------------

   function Less_Case_Insensitive (Left, Right : Class_Instance) return Boolean
   is
      Property_Left      : Code_Analysis_Property_Record;
      Property_Right     : Code_Analysis_Property_Record;
      Miss_Instance_Name : exception;
   begin
      Property_Left := Code_Analysis_Property_Record
        (Get_Property (Left, Code_Analysis_Cst_Str));
      Property_Right := Code_Analysis_Property_Record
        (Get_Property (Right, Code_Analysis_Cst_Str));

      if Property_Left.Instance_Name = null then
         raise Miss_Instance_Name with "Property_Left.Instance_Name is null";
      end if;

      if Property_Right.Instance_Name = null then
         raise Miss_Instance_Name with "Property_Right.Instance_Name is null";
      end if;

      return Ada.Strings.Less_Case_Insensitive
        (Property_Left.Instance_Name.all, Property_Right.Instance_Name.all);
   end Less_Case_Insensitive;

   ----------------------------
   -- Equal_Case_Insensitive --
   ----------------------------

   function Equal_Case_Insensitive
     (Left, Right : Class_Instance) return Boolean
   is
      Property_Left      : Code_Analysis_Property_Record;
      Property_Right     : Code_Analysis_Property_Record;
      Miss_Instance_Name : exception;
   begin
      Property_Left := Code_Analysis_Property_Record
        (Get_Property (Left, Code_Analysis_Cst_Str));
      Property_Right := Code_Analysis_Property_Record
        (Get_Property (Right, Code_Analysis_Cst_Str));

      if Property_Left.Instance_Name = null then
         raise Miss_Instance_Name with "Property_Left.Instance_Name is null";
      end if;

      if Property_Right.Instance_Name = null then
         raise Miss_Instance_Name with "Property_Right.Instance_Name is null";
      end if;

      return Ada.Strings.Equal_Case_Insensitive
        (Property_Left.Instance_Name.all, Property_Right.Instance_Name.all);
   end Equal_Case_Insensitive;

   ---------------------
   -- Register_Module --
   ---------------------

   procedure Register_Module
     (Kernel : access GPS.Kernel.Kernel_Handle_Record'Class)
   is
      Contextual_Menu     : Code_Analysis_Contextual_Menu_Access;
      Code_Analysis_Class : constant Class_Type :=
                              New_Class (Kernel, Code_Analysis_Cst_Str);
   begin
      Binary_Coverage_Mode := Active (Binary_Coverage_Trace);
      Code_Analysis_Module_ID := new Code_Analysis_Module_ID_Record;
      Code_Analysis_Module_ID.Kernel := Kernel_Handle (Kernel);
      Code_Analysis_Module_ID.Class  := Code_Analysis_Class;
      Contextual_Menu := new Code_Analysis_Contextual_Menu;
      Register_Module
        (Module      => Code_Analysis_Module_ID,
         Kernel      => Kernel,
         Module_Name => Code_Analysis_Cst_Str);
      Register_Contextual_Submenu
        (Kernel   => Code_Analysis_Module_ID.Kernel,
         Name     => -"Coverage",
         Filter   => new Has_Coverage_Filter,
         Submenu  => Submenu_Factory (Contextual_Menu));
      Register_Dynamic_Menu
        (Kernel      => Kernel,
         Parent_Path => '/' & (-"Tools"),
         Text        => -"Covera_ge",
         Ref_Item    => -"Documentation",
         Add_Before  => False,
         Factory     => Dynamic_Tools_Menu_Factory'Access);
      Register_Dynamic_Menu
        (Kernel      => Kernel,
         Parent_Path => '/' & (-"Tools" & ('/' & (-"Views"))),
         Text        => -"Covera_ge",
         Ref_Item    => -"Clipboard",
         Add_Before  => False,
         Factory     => Dynamic_Views_Menu_Factory'Access);
      Add_Hook
        (Kernel  => Kernel,
         Hook    => Project_Changing_Hook,
         Func    =>
           Wrapper (Destroy_All_Instances_From_Project_Changing_Hook'Access),
         Name    => "destroy_all_code_analysis");
      Register_Command
        (Kernel, Constructor_Method,
         Class   => Code_Analysis_Class,
         Handler => Create_From_Shell'Access);
      Register_Command
        (Kernel, "add_all_gcov_project_info",
         Class   => Code_Analysis_Class,
         Handler => Add_All_Gcov_Project_Info_From_Shell'Access);
      Register_Command
        (Kernel, "add_gcov_project_info",
         Minimum_Args => 1,
         Maximum_Args => 1,
         Class        => Code_Analysis_Class,
         Handler      => Add_Gcov_Project_Info_From_Shell'Access);
      Register_Command
        (Kernel, "add_gcov_file_info",
         Minimum_Args => 2,
         Maximum_Args => 2,
         Class        => Code_Analysis_Class,
         Handler      => Add_Gcov_File_Info_From_Shell'Access);
      Register_Command
        (Kernel, "list_lines_not_covered",
         Class   => Code_Analysis_Class,
         Handler => List_Lines_Not_Covered_In_All_Projects_From_Shell'Access);
      Register_Command
        (Kernel, "show_analysis_report",
         Class   => Code_Analysis_Class,
         Handler => Show_Analysis_Report_From_Shell'Access);
      Register_Command
        (Kernel, Destructor_Method,
         Class   => Code_Analysis_Class,
         Handler => Destroy_From_Shell'Access);
   end Register_Module;

end Code_Analysis_Module;
