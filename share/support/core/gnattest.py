"""
This file provides support for gnattest.
"""

###########################################################################
# No user customization below this line
###########################################################################

import os.path
import GPS
from gps_utils import hook, interactive

GPS.Preference("GNATtest:Colors/read_only_color"
               ).create("Highlight color", "color",
                        """Background color for read-only areas""",
                        "#e0e0e0")

last_gnattest = {
    'project': None,  # project which gnattest run for
    'root':    None,  # root project opened before switching to harness
    'harness': None   # harness project name before switching to it
}


def run(project, target, extra_args=""):
    """ Run gnattest and switch to harness if success. """
    last_gnattest['project'] = project
    GPS.BuildTarget(target).execute(synchronous=False, extra_args=extra_args)


def get_driver_list():
    """ Check if root project has test_drivers.list file and return it. """
    root_project = GPS.Project.root().file().path
    (name, ext) = os.path.splitext(root_project)
    name = name + ".list"
    if os.path.exists(name):
        return name
    else:
        return ""


def get_harness_project_file(cur):
    """ Return name of harness project with last modification time """
    harness_dir = cur.get_attribute_as_string("Harness_Dir", "GNATtest")
    project_dir = cur.file().directory()
    object_dir = cur.get_attribute_as_string("Object_Dir")
    parent_dir = os.path.join(project_dir, object_dir)

    list = []

    if harness_dir == "":
        list.append(os.path.join(parent_dir,
                                 "gnattest", "harness",
                                 "test_driver.gpr"))
        list.append(os.path.join(parent_dir,
                                 "gnattest_stub", "harness",
                                 "test_drivers.gpr"))
    else:
        list.append(os.path.join(parent_dir,
                                 harness_dir,
                                 "test_driver.gpr"))
        list.append(os.path.join(parent_dir,
                                 harness_dir,
                                 "test_drivers.gpr"))

    def compare(a, b):
        if not os.path.exists(a):
            return b
        elif not os.path.exists(b) or \
                os.path.getmtime(a) > os.path.getmtime(b):

            return a
        else:
            return b

    return reduce(compare, list, "")


def open_harness_project(cur):
    """ Open harness project if it hasn't open yet."""
    if GPS.Project.root().is_harness_project():
        return

    prj = get_harness_project_file(cur)

    if os.path.exists(prj):
        last_gnattest['root'] = GPS.Project.root().file().path
        GPS.Project.load(prj, False, True)
        GPS.Console("Messages").write("Switched to harness project: " +
                                      GPS.Project.root().file().path + "\n")
        last_gnattest['harness'] = GPS.Project.root().file().path
    else:
        GPS.Console("Messages").write("No harness project found: %s!\n" %
                                      (prj))


def exit_harness_project():
    """ Leave harness project and open user's project. """
    root_project = GPS.Project.root()

    if last_gnattest['harness'] == root_project.file().path:
        user_project = last_gnattest['root']
    else:
        user_project = root_project.original_project().file().path

    GPS.Project.load(user_project, False, True)
    GPS.Console("Messages").write("Exit harness project to: " +
                                  GPS.Project.root().file().path + "\n")


@hook('compilation_finished')
def __on_compilation_finished(category, target_name="",
                              mode_name="", status=""):

    if not target_name.startswith("GNATtest"):
        return

    if status:
        return

    open_harness_project(last_gnattest['project'])


def __update_build_targets_visibility():
    """
    Update the GNATtest/'Run Main' Build Targets visibility regarding
    the nature of the loaded project.
    """
    test_run_target = GPS.BuildTarget("Run a test-driver")
    test_run_targets = GPS.BuildTarget("Run a test drivers list")
    run_main_target = GPS.BuildTarget("Run Main")

    if not GPS.Project.root().is_harness_project():
        run_main_target.show()
        test_run_target.hide()
        test_run_targets.hide()
        return
    elif get_driver_list() == "":
        run_main_target.hide()
        test_run_target.show()
        test_run_targets.hide()
    else:
        run_main_target.hide()
        test_run_target.hide()
        test_run_targets.show()


@hook('gps_started')
def on_gps_start():
    """
    Make sure that the 'Run main' build target is not hidden when opening
    GPS with a non-harness project.
    """
    __update_build_targets_visibility()


@hook('project_view_changed')
def on_project_view_changed():
    """ Replace run target in harness project. """
    __update_build_targets_visibility()

    # Update read-only areas in already opened files
    buffer_list = GPS.EditorBuffer.list()
    for buffer in buffer_list:
        mark_read_only_areas(buffer)


@hook('file_edited')
def __on_file_edited(file):
    """ Find read-only areas and apply an overlay on them. """
    if not GPS.Project.root().is_harness_project():
        return

    buffer = GPS.EditorBuffer.get(file)
    mark_read_only_areas(buffer)


def mark_read_only_areas(buffer):
    read_only_overlay = None
    loc = buffer.beginning_of_buffer()

    # Iterate over read-only areas
    while loc:
        found = loc.search("--  begin read only", dialog_on_failure=False)

        if found:
            from_line, last = found
            found = last.search("--  end read only", dialog_on_failure=False)

            if found:
                to_line, loc = found
            else:
                loc = None

        else:
            loc = None

        # if area found
        if loc:
            from_line = from_line.beginning_of_line()
            to_line = to_line.end_of_line()

            # if overlay hasn't exist yet, create one
            if not read_only_overlay:
                read_only_overlay = buffer.create_overlay()
                color = GPS.Preference("GNATtest:Colors/read_only_color"
                                       ).get()
                read_only_overlay.set_property("paragraph-background", color)
                read_only_overlay.set_property("editable", False)

            buffer.apply_overlay(read_only_overlay, from_line, to_line)
    # No more read-only areas


def open_harness_filter(context):
    if GPS.Project.root().is_harness_project():
        return False

    if not isinstance(context, GPS.FileContext):
        return False

    project = context.project()

    if not project:
        return False

    return os.path.exists(get_harness_project_file(project))


@interactive("General", open_harness_filter, name="open harness",
             contextual="GNATtest/Open harness project")
def open_harness():
    """
    Open harness project for current project
    """
    open_harness_project(GPS.current_context().project())


XML = r"""<?xml version="1.0" ?>
<gnattest>
  <project_attribute package="gnattest"
    name="harness_dir"
    editor_page="GNATtest"
    editor_section="Directories"
    label="Harness Directory"
    description="Used to specify the directory in which to """ \
    """place harness packages and project file for the test driver."
    hide_in="wizard library_wizard"
    >
    <string type="directory" default="gnattest/harness"/>
  </project_attribute>

  <project_attribute package="gnattest"
    name="tests_dir"
    editor_page="GNATtest"
    editor_section="Directories"
    disable_if_not_set="true"
    disable="gnattest.tests_root gnattest.subdir"
    label="Tests Directory"
    description="Directory in which Test Files are put."
    hide_in="wizard library_wizard"
    >
    <string default="gnatest/tests"/>
  </project_attribute>

  <project_attribute package="gnattest"
    name="tests_root"
    editor_page="GNATtest"
    editor_section="Directories"
    disable_if_not_set="true"
    disable="gnattest.tests_dir gnattest.subdir"
    label="Tests Root"
    description="Test files are put in a same directory hierarchy """ \
    """as the sources with this directory as the root directory."
    hide_in="wizard library_wizard"
    />

  <project_attribute package="gnattest"
    name="subdir"
    editor_page="GNATtest"
    editor_section="Directories"
    disable_if_not_set="true"
    disable="gnattest.tests_dir gnattest.tests_root"
    label="Stub Subdir"
    description="Place the Test Packages in subdirectories."
    hide_in="wizard library_wizard"
    >
  </project_attribute>

  <project_attribute package="gnattest"
    name="additional_tests"
    editor_page="GNATtest"
    label="Additional Tests"
    description="Sources described in given project are considered """ \
    """potential additional manual tests to be added to the test suite."
    hide_in="wizard library_wizard"
    >
    <string type="file" filter="project"/>
  </project_attribute>

  <project_attribute package="gnattest"
    name="stubs_default"
    editor_page="GNATtest"
    label="Stubs Default"
    description="Default behavior of generated stubs."
    hide_in="wizard library_wizard"
    >
    <choice default="true">fail</choice>
    <choice>pass</choice>
  </project_attribute>

  <project_attribute package="gnattest"
    name="gnattest_switches"
    editor_page="GNATtest"
    list="true"
    label="GNATtest Switches"
    description="Custom switches for gnattest."
    hide_in="wizard library_wizard"
    >
    <string default=""/>
  </project_attribute>

  <project_attribute package="gnattest"
    name="gnattest_mapping_file"
    hide_in="all"
    editor_page="GNATtest"
    label="GNATtest Mapping File"
    description="Map tests to subprograms."
    />

  <action name="run gnattest">
    <filter_and>
      <filter id="Project only"/>
      <filter id="Non harness project"/>
    </filter_and>
    <description>Run gnattest on current project</description>
    <shell lang="python" output="none"
    >gnattest.run(GPS.current_context().project(), """ \
    """"GNATtest for project")</shell>
  </action>

  <action name="run gnattest on root">
    <filter_and>
      <filter id="Non harness project"/>
    </filter_and>
    <description>Run gnattest on root project</description>
    <shell lang="python" output="none"
    >gnattest.run(GPS.Project.root(), "GNATtest for root project")</shell>
  </action>

  <action name="exit harness" output="none">
    <filter id="Harness project"/>
    <description>Return to user project from current """ \
    """harness project</description>
    <shell lang="python">gnattest.exit_harness_project()</shell>
  </action>

  <action name="make single test" output="none">
    <filter_and>
      <filter id="Library package declaration"/>
      <filter id="Non harness project"/>
    </filter_and>
    <description>Run gnattest on single package</description>
    <shell lang="python" output="none"
    >gnattest.run(GPS.current_context().project(), "GNATtest for file")</shell>
  </action>

  <contextual action="run gnattest" after="GNATtest">
    <title>GNATtest/Generate unit test setup for %p</title>
  </contextual>

  <contextual action="exit harness" after="GNATtest">
    <title>GNATtest/Exit harness project</title>
  </contextual>

  <contextual action="make single test" after="GNATtest">
    <title>GNATtest/Generate unit test setup for %f</title>
  </contextual>

  <target-model name="gnattest" category="">
    <description>Generic launch of gnattest</description>
    <command-line>
      <arg>%gnat</arg>
      <arg>test</arg>
      <arg>-dd</arg>
      <arg>-P%pp</arg>
      <arg>%X</arg>
    </command-line>
    <iconname>gps-build-all-symbolic</iconname>
    <switches command="gnattest" columns="2" lines="1">
      <title column="1" line="1">Files and directories</title>
      <title column="2" line="1">Other switches</title>
      <field label="harness directory"
             line="1"  column="1"
             switch="--harness-dir"
             separator="="
             as-directory="true"
             tip="is used to specify the directory in which to """ \
"""place harness packages and project file for the test driver." />
      <field label="separate tests root"
             line="1"  column="1"
             switch="--tests-root"
             separator="="
             as-directory="true"
             tip="The directory hierarchy of tested sources is """ \
    """recreated in this directory, and test packages are placed in """ \
    """corresponding directories." />
      <field label="stub subdir"
             line="1"  column="1"
             switch="--subdir"
             separator="="
             as-directory="true"
             tip="Test packages are placed in subdirectories" />
      <field label="tests directory"
             line="1"  column="1"
             switch="--tests-dir"
             separator="="
             as-directory="true"
             tip="All test packages are placed in this directory." />
      <field label="additional tests"
             line="1"  column="1"
             switch="--additional-tests"
             separator="="
             as-file="true"
             tip="Sources described in given project are considered """ \
    """potential additional manual tests to be added to the test suite." />
      <combo label="skeletons default"
             line="2"  column="1"
             switch="--skeleton-default"
             separator="="
             noswitch="fail"
             tip="Default behavior of generated skeletons.">
        <combo-entry label="Fail" value="fail"/>
        <combo-entry label="Pass" value="pass"/>
      </combo>
      <check label="use stubbing"
             line="1"  column="2"
             switch="--stub"
             tip="Generates the testing framework that uses subsystem """ \
    """stubbing to isolate the code under test. " />
      <check label="generate harness only"
             line="1"  column="2"
             switch="--harness-only"
             tip="Create a harness for all sources, treating them as """ \
    """test packages." />
      <check label="recursive"
             line="1"  column="2"
             switch="-r"
             tip="Recursively consider all sources from all projects." />
      <check label="silent"
             line="1"  column="2"
             switch="-q"
             tip="Suppresses noncritical output messages." />
      <check label="verbose"
             line="1"  column="2"
             switch="-v"
             tip="Verbose mode: generates version information." />
      <check label="validate type ext."
             line="1"  column="2"
             switch="--validate-type-extensions"
             tip="Enables substitution check: run all tests from all """ \
    """parents in order to check substitutability." />
    </switches>
  </target-model>

  <!-- This is model for run test-driver executables generated by GNATtest -->
  <target-model name="GNATtest run" category="">
    <description>Run a test-driver generated by GNATtest</description>
    <is-run>FALSE</is-run>
    <command-line>
      <arg>%E</arg>
      <arg>--passed-tests=hide</arg>
    </command-line>
    <server>Execution_Server</server>
    <iconname>gps-run-symbolic</iconname>

    <switches command="%(tool_name)s" columns="1" separator="=">
      <combo label="Default test behavior "
        switch="--skeleton-default="
        tip="How to count unimplemented tests in this run">
        <combo-entry label="Pass" value="pass"/>
        <combo-entry label="Fail" value="fail"/>
      </combo>

      <check label="Suppress passed tests output"
        switch="--passed-tests=hide"
        switch-off="--passed-tests=show"
        default="on"
        tip="hide passed tests from test river output"/>

    </switches>
  </target-model>

  <!-- This is model for run test-drivers.list generated by GNATtest -->
  <target-model name="GNATtest execution mode" category="">
    <description>Run a test-drivers.list generated by GNATtest</description>
    <is-run>FALSE</is-run>
    <command-line>
      <arg>%gnat</arg>
      <arg>test</arg>
      <arg>test_drivers.list</arg>
      <arg>--passed-tests=hide</arg>
    </command-line>
    <server>Execution_Server</server>
    <iconname>gps-run-symbolic</iconname>

    <switches command="%(tool_name)s" columns="1" separator="=">
      <spin label="Runs N tests in parallel"
        switch="--queues=" min="1" default="1"
        tip="Runs n tests in parallel (default is 1)." />

      <check label="Suppress passed tests output"
        switch="--passed-tests=hide"
        switch-off="--passed-tests=show"
        default="on"
        tip="hide passed tests from test river output"/>

    </switches>
  </target-model>

  <target model="gnattest" category="_Project_" name="GNATtest for project">
    <in-menu>FALSE</in-menu>
    <launch-mode>MANUALLY_WITH_DIALOG</launch-mode>
    <read-only>TRUE</read-only>

    <command-line>
      <arg>%gnat</arg>
      <arg>test</arg>
      <arg>-dd</arg>
      <arg>-P%pp</arg>
      <arg>%X</arg>
    </command-line>
  </target>

  <target model="gnattest" category="_File_" name="GNATtest for file">
    <in-toolbar>FALSE</in-toolbar>
    <in-menu>FALSE</in-menu>
    <launch-mode>MANUALLY_WITH_DIALOG</launch-mode>
    <read-only>TRUE</read-only>

    <command-line>
      <arg>%gnat</arg>
      <arg>test</arg>
      <arg>-dd</arg>
      <arg>-P%pp</arg>
      <arg>%X</arg>
      <arg>%F</arg>
    </command-line>
  </target>

  <target model="gnattest" category="_Project_"
          name="GNATtest for root project">
    <in-menu>FALSE</in-menu>
    <launch-mode>MANUALLY_WITH_DIALOG</launch-mode>
    <read-only>TRUE</read-only>

    <command-line>
      <arg>%gnat</arg>
      <arg>test</arg>
      <arg>-dd</arg>
      <arg>-P%PP</arg>
      <arg>%X</arg>
    </command-line>
  </target>

  <target model="GNATtest run" category="Run"
          name="Run a test-driver"
          messages_category="test-driver">
    <visible>FALSE</visible>
    <in-menu>TRUE</in-menu>
    <in-toolbar>TRUE</in-toolbar>
    <in-contextual-menus-for-projects>TRUE</in-contextual-menus-for-projects>
    <launch-mode>MANUALLY_WITH_DIALOG</launch-mode>
    <target-type>executable</target-type>
    <command-line>
      <arg>%E</arg>
      <arg>--passed-tests=hide</arg>
    </command-line>
    <iconname>gps-gnattest-run</iconname>
  </target>

  <target model="GNATtest execution mode" category="Run"
          name="Run a test drivers list"
          messages_category="test-driver">
    <visible>FALSE</visible>
    <in-menu>TRUE</in-menu>
    <in-toolbar>TRUE</in-toolbar>
    <in-contextual-menus-for-projects>TRUE</in-contextual-menus-for-projects>
    <launch-mode>MANUALLY_WITH_DIALOG</launch-mode>
    <target-type>executable</target-type>
    <command-line>
      <arg>%gnat</arg>
      <arg>test</arg>
      <arg>test_drivers.list</arg>
      <arg>--passed-tests=hide</arg>
    </command-line>
    <iconname>gps-gnattest-run</iconname>
  </target>

</gnattest>
"""

GPS.parse_xml(XML)
