------------------------------------------------------------------------------
--                                  G P S                                   --
--                                                                          --
--                       Copyright (C) 2017, AdaCore                        --
--                                                                          --
-- This is free software;  you can redistribute it  and/or modify it  under --
-- terms of the  GNU General Public License as published  by the Free Soft- --
-- ware  Foundation;  either version 3,  or (at your option) any later ver- --
-- sion.  This software is distributed in the hope  that it will be useful, --
-- but WITHOUT ANY WARRANTY;  without even the implied warranty of MERCHAN- --
-- TABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public --
-- License for  more details.  You should have  received  a copy of the GNU --
-- General  Public  License  distributed  with  this  software;   see  file --
-- COPYING3.  If not, go to http://www.gnu.org/licenses for a complete copy --
-- of the license.                                                          --
------------------------------------------------------------------------------

with System.Storage_Elements;
with Interfaces.C;
with LAL.Switching_Tree_Providers; use LAL.Switching_Tree_Providers;
with Language.Ada;
with Libadalang.Analysis.C;
with GNATCOLL.Python;
with GNATCOLL.Scripts.Python;      use GNATCOLL.Scripts.Python;
with GNATCOLL.Scripts;             use GNATCOLL.Scripts;
with GPS.Editors;
with GPS.Scripts;

package body LAL.Module is

   Module : LAL_Module_Id;

   procedure Get_Analysis_Unit_Shell
     (Data    : in out Callback_Data'Class;
      Command : String);
   --  Execute 'get_analysis_unit' script command

   -----------------------------
   -- Get_Analysis_Unit_Shell --
   -----------------------------

   procedure Get_Analysis_Unit_Shell
     (Data    : in out Callback_Data'Class;
      Command : String)
   is
      pragma Unreferenced (Command);

      Kernel : constant GPS.Core_Kernels.Core_Kernel :=
        GPS.Scripts.Get_Kernel (Data);

      Python : constant Scripting_Language :=
        Kernel.Scripts.Lookup_Scripting_Language ("Python");

      Editor_Buffer_Class : constant Class_Type :=
        Kernel.Scripts.New_Class ("EditorBuffer");

      Instance : constant Class_Instance :=
        Nth_Arg (Data, 1, Editor_Buffer_Class);

      Buffer : constant GPS.Editors.Editor_Buffer'Class :=
        Kernel.Get_Buffer_Factory.Buffer_From_Instance (Instance);

      Unit   : Libadalang.Analysis.Analysis_Unit;
      Unit_C : Libadalang.Analysis.C.ada_analysis_unit;
      Int    : System.Storage_Elements.Integer_Address;
      Value  : GNATCOLL.Python.PyObject;
      Args   : Callback_Data'Class := Python.Create (1);
   begin
      Unit := Libadalang.Analysis.Get_From_Buffer
        (Context     => Module.Context,
         Filename    => Buffer.File.Display_Full_Name,
         Buffer      => Buffer.Get_Chars);

      Unit_C := Libadalang.Analysis.C.Wrap (Unit);
      Int := System.Storage_Elements.To_Integer (System.Address (Unit_C));
      Value := GNATCOLL.Python.PyInt_FromSize_t (Interfaces.C.size_t (Int));
      Python_Callback_Data'Class (Args).Set_Nth_Arg (1, Value);

      Args.Execute_Command ("libadalang.AnalysisUnit._wrap");
      Data.Set_Return_Value (Class_Instance'(Args.Return_Value));
   end Get_Analysis_Unit_Shell;

   ---------------------
   -- Register_Module --
   ---------------------

   procedure Register_Module
     (Kernel : access GPS.Core_Kernels.Core_Kernel_Record'Class;
      Config : Use_LAL_Configuration)
   is
      Editor_Buffer_Class : constant Class_Type :=
        Kernel.Scripts.New_Class ("EditorBuffer");
   begin
      Module         := new LAL_Module_Id_Record;
      Module.Kernel  := GPS.Core_Kernels.Core_Kernel (Kernel);
      Module.Context := Libadalang.Analysis.Create
        (Unit_Provider => Module.Unit_Provider'Access);

      Module.Unit_Provider.Initialize (GPS.Core_Kernels.Core_Kernel (Kernel));

      Kernel.Scripts.Register_Command
        (Command => "get_analysis_unit",
         Class   => Editor_Buffer_Class,
         Handler => Get_Analysis_Unit_Shell'Access);

      Kernel.Register_Tree_Provider
        (Language.Ada.Ada_Lang,
         new Provider'(Config, (Module.Kernel, Module.Context)));

      Kernel.Register_Module (GPS.Core_Kernels.Abstract_Module (Module));
   end Register_Module;

end LAL.Module;
