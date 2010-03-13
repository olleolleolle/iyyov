# -*- ruby -*-
#--
# Copyright (C) 2010 David Kellum
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

$LOAD_PATH << './lib'

require 'rubygems'
gem     'rjack-tarpit', '~> 1.2.0'
require 'rjack-tarpit'

require 'iyyov/base'

t = RJack::TarPit.new( 'iyyov', Iyyov::VERSION, :java_platform )

t.specify do |h|
  h.developer( 'David Kellum', 'dek-oss@gravitext.com' )
  h.testlib = :minitest
  h.extra_deps     += [ [ 'rjack-slf4j',         '~> 1.5.11' ],
                        [ 'rjack-logback',       '~> 0.9.18' ],
                        [ 'logrotate',           '=  1.2.1'  ] ]
  h.extra_dev_deps += [ [ 'minitest',            '~> 1.5.0'  ],
                        [ 'hashdot-test-daemon', '>= 1.0.0'  ] ]
end

# Version/date consistency checks:

task :chk_init_v do
  t.test_line_match( 'init/iyyov-daemon',
                      /^gem.+#{t.name}/, /= #{t.version}/ )
end
task :chk_rcd_v do
  t.test_line_match( 'samples/init.d/iyyov', /^version=".+"/, /"#{t.version}"/ )
end
task :chk_hist_v do
  t.test_line_match( 'History.rdoc', /^==/, / #{t.version} / )
end
task :chk_hist_date do
  t.test_line_match( 'History.rdoc', /^==/, /\([0-9\-]+\)$/ )
end

task :gem  => [ :chk_init_v, :chk_rcd_v, :chk_hist_v ]
task :tag  => [ :chk_init_v, :chk_rcd_v, :chk_hist_v, :chk_hist_date ]
task :push => [                                       :chk_hist_date ]

t.define_tasks
