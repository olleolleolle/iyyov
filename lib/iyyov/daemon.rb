#--
# Copyright (c) 2010-2016 David Kellum
#
# Licensed under the Apache License, Version 2.0 (the "License"); you
# may not use this file except in compliance with the License.  You
# may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
# implied.  See the License for the specific language governing
# permissions and limitations under the License.
#++

require 'rjack-slf4j'
require 'fileutils'

require 'iyyov/log_rotator'

module Iyyov

  # A daemon instance to start and monitor
  class Daemon
    include RJack

    # Name of this daemon. Must be unique in combination with any
    # specified instance.
    #
    # String (required)
    attr_accessor :name

    # Optional specific instance identifier, distinguishing this
    # daemon from others of the same name. For example, a port number
    # could be used.
    #
    # Proc,~to_s (default: nil)
    attr_writer   :instance

    # Full path to executable to start.
    #
    # Proc,~to_s (default: compute from gem_name, init_name, and version)
    attr_writer   :exe_path

    # Any additional args to use on start
    #
    # Proc,Array[~to_s] (default: [])
    attr_writer   :args

    # Base directory under which run directories are found
    #
    # Proc,~to_s (default: Context.base_dir)
    attr_writer   :base_dir

    # Directory to execute under
    #
    # Proc,~to_s (default: base_dir / full_name)
    attr_writer   :run_dir

    # Whether to make run_dir, if not already present
    #
    # Boolean (default: Context.make_run_dir )
    attr_accessor :make_run_dir

    # Whether to stop this daemon when Iyyov exits
    #
    # Boolean (default: Context.stop_on_exit)
    attr_accessor :stop_on_exit

    # Duration in seconds between SIGTERM and final SIGKILL when
    # stopping.
    #
    # Numeric (default: Context.stop_delay)
    attr_accessor :stop_delay

    # PID file written by the daemon process after start, containing
    # the running daemon Process ID
    #
    # Proc,~to_s (default: run_dir, init_name + '.pid')
    attr_writer   :pid_file

    # The gem name used, in conjunction with version for gem-based
    # default exe_path
    #
    # Proc,~to_s (default: name)
    attr_writer   :gem_name

    # The gem version requirements, i.e '~> 1.1.3'
    #
    # Proc,~to_s,Array[~to_s] (default: '>= 0')
    attr_writer   :version

    # The init script name used for gem-based default exe_path.
    #
    # Proc,~to_s (default: name)
    attr_writer   :init_name

    # Last found state of this daemon.
    #
    # Symbol (in STATES)
    attr_reader   :state

    # SLF4J logger
    attr_reader   :log

    # States tracked
    STATES = [ :begin, :up, :failed, :stopped ]

    # Instance variables which may be set as Procs
    LVARS = [ :@instance, :@exe_path, :@args, :@base_dir, :@run_dir, :@pid_file,
              :@gem_name, :@version, :@init_name ]

    # New daemon given specified or default global
    # Iyyov.context. Yields self to block for configuration.
    def initialize( context = Iyyov.context )

      @context      = context
      @name         = nil

      @instance     = nil
      @exe_path     = method :gem_exe_path
      @args         = []
      @base_dir     = method :default_base_dir
      @run_dir      = method :default_run_dir
      @make_run_dir = @context.make_run_dir
      @stop_on_exit = @context.stop_on_exit
      @stop_delay   = @context.stop_delay

      @pid_file     = method :default_pid_file
      @gem_name     = method :name
      @version      = '>= 0'
      @init_name    = method :name

      @state        = :begin
      @gem_spec     = nil
      @rotators     = {}

      yield self if block_given?

      raise "name not specified" unless name

      @log = SLF4J[ [ SLF4J[ self.class ].name,
                      name, instance ].compact.join( '.' ) ]
    end

    # Given name + ( '-' + instance ) if provided.
    def full_name
      [ name, instance ].compact.join('-')
    end

    # Create a new LogRotator and yields it to block for
    # configuration.
    # The default log path is name + ".log" in run_dir
    def log_rotate( &block )
      lr = LogRotator.new( default_log, &block )
      @rotators[ lr.log ] = lr
      nil
    end

    # Post initialization validation, attempt immediate start if
    # needed, and add appropriate tasks to scheduler.
    def do_first( scheduler )
      unless File.directory?( run_dir )
        if make_run_dir
          @log.info { "Creating run_dir [#{run_dir}]." }
          FileUtils.mkdir_p( run_dir, :mode => 0755 )
        else
          raise( DaemonFailed, "run_dir [#{run_dir}] not found" )
        end
      end

      res = start_check
      unless res == :stop
        tasks.each { |t| scheduler.add( t ) }
      end
      res
    rescue DaemonFailed, SystemCallError => e
      #FIXME: Ruby 1.4.0 throws SystemCallError when mkdir fails from
      #permissions
      @log.error( "Do first", e )
      @state = :failed
      :stop
    end

    def tasks
      t = [ Task.new( :name => full_name, :period => 5.0 ) { start_check } ]
      t += @rotators.values.map do |lr|
        Task.new( :name => "#{full_name}.rotate",
                  :mode => :async,
                  :period => lr.check_period ) do
          lr.check_rotate( pid ) do |rlog|
            @log.info { "Rotating log #{rlog}" }
          end
        end
      end
      t
    end

    def do_exit
      stop if stop_on_exit
    end

    def default_base_dir
      @context.base_dir
    end

    def default_run_dir
      File.join( base_dir, full_name )
    end

    def default_pid_file
      in_dir( init_name + '.pid' )
    end

    def default_log
      in_dir( init_name + '.log' )
    end

    # Return full path to file_name within run_dir
    def in_dir( file_name )
      File.join( run_dir, file_name )
    end

    def gem_exe_path
      File.join( find_gem_spec.full_gem_path, 'init', init_name )
    end

    def find_gem_spec
      @gem_spec ||=
        if Gem::Specification.respond_to?( :find_by_name )
          Gem::Specification.find_by_name( gem_name, version )
        else
          Gem.source_index.find_name( gem_name, version ).last
        end
      unless @gem_spec
        raise( Gem::GemNotFoundException, "Missing gem #{gem_name} (#{version})" )
      end
      @gem_spec
    end

    def start
      epath = File.expand_path( exe_path )
      eargs = args.map { |a| a.to_s.strip }.compact
      aversion = @gem_spec && @gem_spec.version
      @log.info { ( [ "starting", aversion || epath ] + eargs ).join(' ') }

      unless File.executable?( epath )
        raise( DaemonFailed, "Exe path: #{epath} not found/executable." )
      end

      Dir.chdir( run_dir ) do
        system( epath, *eargs ) or raise( DaemonFailed, "Start failed with #{$?}" )
      end

      @state = :up
      true
    rescue Gem::LoadError, Gem::GemNotFoundException, DaemonFailed, Errno::ENOENT => e
      @log.error( "On exec", e )
      @state = :failed
      false
    end

    # Return true if passes initial checks for start. This includes
    # gem availability and/or if the exe_path is executable,
    # i.e. everything that can be checked *before* starting.
    def pre_check
      epath = File.expand_path( exe_path )
      is_exec = File.executable?( epath )
      @log.warn( "#{epath} is not executable" ) unless is_exec
      is_exec
    rescue Gem::LoadError, Gem::GemNotFoundException, Errno::ENOENT => e
      @log.warn( e.to_s )
      false
    end

    # Return array suitable for comparing this daemon with prior
    # running instance.
    def exec_key
      epath = begin
                exe_path
              rescue Gem::LoadError, Gem::GemNotFoundException => e
                @log.warn( e.to_s )
                # Use a bogus, unique path instead
                "/tmp/gem-not-found/#{ Time.now.usec }/#{ rand( 2**31 ) }"
              end

      keys = [ run_dir, epath ].map { |p| File.expand_path( p ) }
      keys += args.map { |a| a.to_s.strip }
      keys.compact
    end

    def start_check
      p = pid
      if alive?( p )
        @log.debug { "checked: alive pid: #{p}" }
        @state = :up
      else
        unless start
          @log.info "start failed, done trying"
          :stop
        end
      end
    end

    # True if process is up
    def alive?( p = pid )
      ( Process.getpgid( p ) != -1 ) if p
    rescue Errno::ESRCH
      false
    end

    # Stop via SIGTERM, waiting for shutdown for up to stop_delay, then
    # SIGKILL as last resort. Return true if a process was stopped.
    def stop
      p = pid
      if p
        @log.info "Sending TERM signal"
        Process.kill( "TERM", p )
        unless wait_pid( p )
          @log.info "Sending KILL signal"
          Process.kill( "KILL", p )
        end
        @status = :stopped
        true
      end
      false
    rescue Errno::ESRCH
      # No such process: only raised by MRI ruby currently
      false
    rescue Errno::EPERM => e
      # Not permitted: only raised by MRI ruby currently
      @log.error( "On stop", e )
      false
    end

    # Wait for process to go away
    def wait_pid( p = pid )
      delta = 1.0 / 16
      delay = 0.0
      check = false
      while delay < stop_delay do
        break if ( check = ! alive?( p ) )
        sleep delta
        delay += delta
        delta += ( 1.0 / 16 ) if delta < 0.50
      end
      check
    end

    # Return process ID from pid_file if exists or nil otherwise
    def pid
      id = IO.read( pid_file ).strip.to_i
      ( id > 0 ) ? id : nil
    rescue Errno::ENOENT # Pid file doesn't exist
      nil
    end

    LVARS.each do |sym|
      define_method( sym.to_s[1..-1] ) do
        exp = instance_variable_get( sym )
        exp.respond_to?( :call ) ? exp.call : exp
      end
    end

  end

  class DaemonFailed < StandardError; end
end
