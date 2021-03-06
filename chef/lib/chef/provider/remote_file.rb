#
# Author:: Adam Jacob (<adam@opscode.com>)
# Copyright:: Copyright (c) 2008 Opscode, Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'chef/provider/file'
require 'chef/rest'
require 'uri'
require 'tempfile'
require 'net/https'

class Chef
  class Provider
    class RemoteFile < Chef::Provider::File

      def load_current_resource
        super
        @current_resource.checksum(checksum(@current_resource.path)) if ::File.exist?(@current_resource.path)
      end

      def action_create
        assert_enclosing_directory_exists!

        Chef::Log.debug("#{@new_resource} checking for changes")

        if current_resource_matches_target_checksum?
          Chef::Log.debug("#{@new_resource} checksum matches target checksum (#{@new_resource.checksum}) - not updating")
        else
          Chef::REST.new(@new_resource.source, nil, nil).fetch(@new_resource.source) do |raw_file|
            if matches_current_checksum?(raw_file)
              Chef::Log.debug "#{@new_resource} target and source checksums are the same - not updating"
            else
              backup_new_resource
              FileUtils.cp raw_file.path, @new_resource.path
              Chef::Log.info "#{@new_resource} updated"
              @new_resource.updated_by_last_action(true)
            end
          end
        end
        enforce_ownership_and_permissions

        @new_resource.updated_by_last_action?
      end

      def action_create_if_missing
        if ::File.exists?(@new_resource.path)
          Chef::Log.debug("#{@new_resource} exists, taking no action.")
        else
          action_create
        end
      end

      def enforce_ownership_and_permissions
        set_owner if @new_resource.owner
        set_group if @new_resource.group
        set_mode  if @new_resource.mode
      end

      def current_resource_matches_target_checksum?
        @new_resource.checksum && @current_resource.checksum && @current_resource.checksum =~ /^#{Regexp.escape(@new_resource.checksum)}/
      end

      def matches_current_checksum?(candidate_file)
        Chef::Log.debug "#{@new_resource} checking for file existence of #{@new_resource.path}"
        if ::File.exists?(@new_resource.path)
          Chef::Log.debug "#{@new_resource} file exists at #{@new_resource.path}"
          @new_resource.checksum(checksum(candidate_file.path))
          Chef::Log.debug "#{@new_resource} target checksum: #{@current_resource.checksum}"
          Chef::Log.debug "#{@new_resource} source checksum: #{@new_resource.checksum}"

          @new_resource.checksum == @current_resource.checksum
        else
          Chef::Log.debug "#{@new_resource} creating #{@new_resource.path}"
          false
        end
      end

      def backup_new_resource
        if ::File.exists?(@new_resource.path)
          Chef::Log.debug "#{@new_resource} checksum changed from #{@current_resource.checksum} to #{@new_resource.checksum}"
          backup @new_resource.path
        end
      end

      def source_file(source, current_checksum, &block)
        if absolute_uri?(source)
          fetch_from_uri(source, &block)
        elsif !Chef::Config[:local]
          fetch_from_chef_server(source, current_checksum, &block)
        else
          fetch_from_local_cookbook(source, &block)
        end
      end

      private

      def absolute_uri?(source)
        URI.parse(source).absolute?
      rescue URI::InvalidURIError
        false
      end

    end
  end
end
