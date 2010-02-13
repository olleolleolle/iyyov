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
gem     'rjack-tarpit', '~> 1.1.0'
require 'rjack-tarpit'

require 'iyyov/base'

t = RJack::TarPit.new( 'iyyov', Iyyov::VERSION )

t.specify do |h|
  h.developer( 'David Kellum', 'dek-oss@gravitext.com' )
  h.testlib = :minitest
end

t.define_tasks
