# frozen_string_literal: true

require 'active_support'
require 'active_support/core_ext/object'

class DHS::Record

  module Request
    extend ActiveSupport::Concern

    module ClassMethods
      def request(options)
        options ||= {}
        options = deep_merge_with_option_blocks(options)
        options = options.freeze
        if options.is_a?(Array)
          multiple_requests(
            filter_empty_request_options(options)
          )
        else
          single_request(options)
        end
      end

      private

      def deep_merge_with_option_blocks(options)
        return options if DHS::OptionBlocks::CurrentOptionBlock.options.blank?
        if options.is_a?(Hash)
          options.deep_merge(DHS::OptionBlocks::CurrentOptionBlock.options)
        elsif options.is_a?(Array)
          options.map do |option|
            return DHS::OptionBlocks::CurrentOptionBlock.options unless option
            option.deep_merge(DHS::OptionBlocks::CurrentOptionBlock.options)
          end
        end
      end

      def single_request_load_and_merge_remaining_objects!(data, options, endpoint)
        return if options[:all].blank? || !paginated
        load_and_merge_remaining_objects!(
          data: data,
          options: process_options(options, endpoint),
          load_not_paginated_collection: true
        )
      end

      def filter_empty_request_options(options)
        options.map do |option|
          option if !option || !option.key?(:url) || !option[:url].nil?
        end
      end

      # Applies limit to the first request of an all request chain
      # Tries to apply an high value for limit and reacts on the limit
      # returned by the endpoint to make further requests
      def apply_limit!(options)
        return if !paginated || options[:all].blank?
        options[:params] ||= {}
        options[:params] = options[:params].merge(limit_key(:parameter) => options[:params][limit_key(:parameter)] || DHS::Pagination::Base::DEFAULT_LIMIT)
      end

      # Convert URLs in options to endpoint templates
      def convert_options_to_endpoints(options)
        if options.is_a?(Array)
          options.map { |request_options| convert_options_to_endpoint(request_options) }
        else
          convert_options_to_endpoint(options)
        end
      end

      def convert_options_to_endpoint(options)
        return if options.blank?
        url = options[:url]
        endpoint = DHS::Endpoint.for_url(url)
        return unless endpoint
        template = endpoint.url
        new_options = options.deep_merge(
          params: DHC::Endpoint.values_as_params(template, url).merge(values_from_get_params(url, options))
        )
        new_options[:url] = template
        new_options
      end

      # Extracts values from url's get parameters
      # and return them as a ruby hash
      def values_from_get_params(url, options)
        uri = parse_uri(url, options)
        return {} if uri.query.blank?
        params = Rack::Utils.parse_nested_query(uri.query).deep_symbolize_keys
        params
      end

      def parse_uri(url, options)
        URI.parse(
          if url.match(Addressable::Template::EXPRESSION)
            compute_url(options[:params], url)
          else
            url
          end
        )
      end

      def handle_includes(includes, data, references = {})
        references ||= {}
        if includes.is_a? Hash
          includes.each { |included, sub_includes| handle_include(included, data, sub_includes, references[included]) }
        elsif includes.is_a? Array
          includes.each do |included|
            handle_includes(included, data, references)
          end
        else
          handle_include(includes, data, nil, references[includes])
        end
        data.clear_cache! if data.present? # as we just included new nested resources
      end

      def handle_include(included, data, sub_includes = nil, reference = nil)
        if data.blank? || skip_loading_includes?(data, included)
          handle_skip_include(included, data, sub_includes, reference)
        else
          options = options_for_data(data, included)
          options = extend_with_reference(options, reference)
          addition = load_existing_includes(options, data, sub_includes, reference)
          data.extend!(addition, included)
          expand_addition!(data, included, reference) unless expanded_data?(addition)
        end
      end

      def handle_skip_include(included, data, sub_includes = nil, reference = nil)
        return if sub_includes.blank?
        handle_includes(sub_includes, data[included], reference)
      end

      def options_for_data(data, included = nil)
        return options_for_multiple(data, included) if data.collection?
        return options_for_nested_items(data, included) if included && data[included].collection?
        url_option_for(data, included)
      end

      def expand_addition!(data, included, reference)
        addition = data[included]
        options = options_for_data(addition)
        options = extend_with_reference(options, reference)
        record = record_for_options(options) || self
        options = convert_options_to_endpoints(options) if record_for_options(options)
        expanded_data = record.request(options)
        data.extend!(expanded_data, included)
      end

      def expanded_data?(addition)
        return false if addition.blank?
        if addition.item?
          (addition._raw.keys - [:href]).any?
        elsif addition.collection?
          addition.any? do |item|
            next if item.blank?
            if item._raw.is_a?(Hash)
              (item._raw.keys - [:href]).any?
            elsif item._raw.is_a?(Array)
              item.any? { |item| (item._raw.keys - [:href]).any? }
            end
          end
        end
      end

      # Extends request options with options provided for this reference
      def extend_with_reference(options, reference)
        return options if reference.blank?
        reference = reference.except(:url)
        options ||= {}
        if options.is_a?(Array)
          options.map { |request_options| request_options.merge(reference) if request_options.present? }
        elsif options.present?
          options.merge(reference)
        end
      end

      def skip_loading_includes?(data, included)
        if data.collection?
          data.to_a.none? { |item| item[included].present? }
        elsif data.dig(included).blank?
          true
        elsif data[included].item? && data[included][:href].blank?
          true
        else
          !data._raw.key?(included)
        end
      end

      # After fetching the first page,
      # we can evaluate if there are further remote objects remaining
      # and after preparing all the requests that have to be made in order to fetch all
      # remote items during this batch, they are fetched in parallel
      def load_and_merge_remaining_objects!(data:, options:, load_not_paginated_collection: false)
        if paginated?(data._raw)
          load_and_merge_paginated_collection!(data, options)
        elsif data.collection? && paginated?(data.first.try(:_raw))
          load_and_merge_set_of_paginated_collections!(data, options)
        elsif load_not_paginated_collection && data.collection?
          warn('[Warning] "all" has been requested, but endpoint does not provide pagination meta data. If you just want to fetch the first response, use "where" or "fetch".')
          load_and_merge_not_paginated_collection!(data, options)
        end
      end

      def load_and_merge_not_paginated_collection!(data, options)
        return if data.length.zero?
        options = options.is_a?(Hash) ? options : {}
        limit = options.dig(:params, limit_key(:parameter)) || pagination_class::DEFAULT_LIMIT
        offset = options.dig(:params, pagination_key(:parameter)) || pagination_class::DEFAULT_OFFSET
        options[:params] = options.fetch(:params, {}).merge(
          limit_key(:parameter) => limit,
          pagination_key(:parameter) => pagination_class.next_offset(
            offset,
            limit
          )
        )
        additional_data = data._record.request(options)
        additional_data.each do |item_data|
          data.concat(input: data._raw, items: [item_data], record: self)
        end
      end

      # sets nested data for a source object that needs to be accessed with a given path e.g. [:response, :total]
      def set_nested_data(source, path, value)
        return source[path] = value unless path.is_a?(Array)
        path = path.dup
        last = path.pop
        path.inject(source, :fetch)[last] = value
      end

      def load_and_merge_paginated_collection!(data, options)
        set_nested_data(data._raw, limit_key(:body), data.length) if data._raw.dig(*limit_key(:body)).blank? && !data.length.zero?
        pagination = data._record.pagination(data)
        return data unless pagination.pages_left?
        record = data._record
        if pagination.parallel?
          load_and_merge_parallel_requests!(record, data, pagination, options)
        else
          load_and_merge_sequential_requests!(record, data, options, data._raw.dig(:next, :href), pagination)
        end
      end

      def load_and_merge_parallel_requests!(record, data, pagination, options)
        record.request(
          options_for_next_batch(record, pagination, options)
        ).each do |batch_data|
          merge_batch_data_with_parent!(batch_data, data)
        end
      end

      def load_and_merge_sequential_requests!(record, data, options, next_link, pagination)
        warn '[WARNING] You are loading all pages from a resource paginated with links only. As this is performed sequentially, it can result in very poor performance! (https://github.com/DePayFi/dhs#pagination-strategy-link).'
        while next_link.present?
          page_data = record.request(
            options.except(:all).merge(url: next_link)
          )
          next_link = page_data._raw.dig(:next, :href)
          merge_batch_data_with_parent!(page_data, data, pagination)
        end
      end

      def load_and_merge_set_of_paginated_collections!(data, options)
        options_for_next_batch = []
        options.each_with_index do |element, index|
          next if element.nil?
          record = data[index]._record
          pagination = record.pagination(data[index])
          next unless pagination.pages_left?
          options_for_next_batch.push(
            options_for_next_batch(record, pagination, options[index]).tap do |options|
              options.each do |option|
                option[:merge_with_index] = index
              end
            end
          )
        end
        data._record.request(options_for_next_batch.flatten).each do |batch_data|
          merge_batch_data_with_parent!(batch_data, data[batch_data._request.options[:merge_with_index]])
        end
      end

      def load_existing_includes(options, data, sub_includes, references)
        if data.collection? && data.any?(&:blank?)
          # filter only existing items
          loaded_includes = load_include(options.compact, data.compact, sub_includes, references)
          # fill up skipped items before returning
          data.each_with_index do |item, index|
            next if item.present?
            loaded_includes.insert(index, {})
          end
          loaded_includes
        else
          load_include(options, data, sub_includes, references)
        end
      end

      # Load additional resources that are requested with include
      def load_include(options, _data, sub_includes, references)
        record = record_for_options(options) || self
        options = convert_options_to_endpoints(options) if record_for_options(options)
        prepare_options_for_include_request!(options, sub_includes, references)
        if references && references[:all] # include all linked resources
          load_include_all!(options, record, sub_includes, references)
        else # simply request first page/batch
          load_include_simple!(options, record)
        end
      end

      def load_include_all!(options, record, sub_includes, references)
        prepare_options_for_include_all_request!(options)
        data = load_all_included!(record, options)
        references.delete(:all) # for this reference all remote objects have been fetched
        continue_including(data, sub_includes, references)
      end

      def load_include_simple!(options, record)
        data = record.request(options)
        warn "[WARNING] You included `#{options[:url]}`, but this endpoint is paginated. You might want to use `includes_all` instead of `includes` (https://github.com/DePayFi/dhs#includes_all-for-paginated-endpoints)." if data && paginated?(data._raw)
        data
      end

      # Continues loading included resources after one complete batch/level has been fetched
      def continue_including(data, included, reference)
        return data if included.blank? || data.blank?
        expand_data!(data, included, reference) unless expanded_data?(data)
        handle_includes(included, data, reference)
        data
      end

      def expand_data!(data, _included, reference)
        options = options_for_data(data)
        options = extend_with_reference(options, reference)
        record = record_for_options(options) || self
        options = convert_options_to_endpoints(options) if record_for_options(options)
        expanded_data = record.request(options)
        data.extend!(expanded_data)
      end

      # Loads all included/linked resources,
      # paginates itself to ensure all records are fetched
      def load_all_included!(record, options)
        data = record.request(options)
        pagination = data._record.pagination(data)
        load_and_merge_remaining_objects!(data: data, options: options) if pagination.parallel?
        data
      end

      def prepare_options_for_include_all_request!(options)
        if options.is_a?(Array)
          options.each do |option|
            prepare_option_for_include_all_request!(option)
          end
        else
          prepare_option_for_include_all_request!(options)
        end
        options
      end

      # When including all resources on one level, don't forward :includes & :references
      # as we have to fetch all resources on this level first, before we continue_including
      def prepare_option_for_include_all_request!(option)
        return option if option.blank? || option[:url].nil?
        uri = parse_uri(option[:url], option)
        get_params = Rack::Utils.parse_nested_query(uri.query)
          .symbolize_keys
          .except(limit_key(:parameter), pagination_key(:parameter))
        option[:params] ||= {}
        option[:params].reverse_merge!(get_params)
        option[:params][limit_key(:parameter)] ||= DHS::Pagination::Base::DEFAULT_LIMIT
        option[:url] = option[:url].gsub("?#{uri.query}", '')
        option.delete(:including)
        option.delete(:referencing)
        option
      end

      def prepare_options_for_include_request!(options, sub_includes, references)
        if options.is_a?(Array)
          options.each { |option| option.merge!(including: sub_includes, referencing: references) if sub_includes.present? }
        elsif sub_includes.present?
          options.merge!(including: sub_includes, referencing: references)
        end
        options || {}
      end

      def merge_batch_data_with_parent!(batch_data, parent_data, pagination = nil)
        parent_data.concat(input: parent_data._raw, items: batch_data.raw_items, record: self)
        return if pagination.present? && pagination.is_a?(DHS::Pagination::Link)
        [limit_key(:body), total_key, pagination_key(:body)].each do |pagination_attribute|
          set_nested_data(
            parent_data._raw,
            pagination_attribute,
            batch_data._raw.dig(*pagination_attribute)
          )
        end
      end

      # Merge explicit params nested in 'params' namespace with original hash.
      def merge_explicit_params!(params)
        return true unless params
        explicit_params = params[:params]
        params.delete(:params)
        params.merge!(explicit_params) if explicit_params
      end

      def multiple_requests(options)
        options = options.map do |option|
          next if option.blank?
          process_options(option, find_endpoint(option[:params], option.fetch(:url, nil)))
        end
        data = DHC.request(options.compact).map do |response|
          DHS::Data.new(response.body, nil, self, response.request)
        end
        including = DHS::Complex.reduce(options.compact.map { |options| options.delete(:including) }.compact)
        referencing = DHS::Complex.reduce(options.compact.map { |options| options.delete(:referencing) }.compact)
        data = restore_with_nils(data, locate_nils(options)) # nil objects in data provide location information for mapping
        data = DHS::Data.new(data, nil, self)
        handle_includes(including, data, referencing) if including.present? && data.present?
        data
      end

      def locate_nils(array)
        nils = []
        array.each_with_index { |value, index| nils << index if value.nil? }
        nils
      end

      def restore_with_nils(array, nils)
        array = array.dup
        nils.sort.each { |index| array.insert(index, nil) }
        array
      end

      def options_for_multiple(data, key = nil)
        data.map do |item|
          url_option_for(item, key)
        end.flatten
      end

      def options_for_nested_items(data, key = nil)
        data[key].map do |item|
          url_option_for(item)
        end.flatten
      end

      def options_for_next_batch(record, pagination, options)
        batch_options = []
        pagination.pages_left.times do |index|
          page_options = {
            params: {
              record.limit_key(:parameter) => pagination.limit,
              record.pagination_key(:parameter) => pagination.next_offset(index + 1)
            }
          }
          batch_options.push(
            options.deep_dup.deep_merge(page_options)
          )
        end
        batch_options
      end

      # Merge explicit params and take configured endpoints options as base
      def process_options(options, endpoint)
        ignored_errors = options[:ignored_errors]
        options = options.deep_dup
        options[:ignored_errors] = ignored_errors if ignored_errors.present?
        options[:params]&.deep_symbolize_keys!
        options[:rescue] = merge_error_handlers(options[:rescue]) if options[:rescue]
        options = (provider_options || {})
          .deep_merge(endpoint.options || {})
          .deep_merge(options)
        options[:url] = compute_url!(options[:params]) unless options.key?(:url)
        merge_explicit_params!(options[:params])
        options.delete(:params) if options[:params]&.empty?
        inject_interceptors!(options)
        options
      end

      def inject_interceptors!(options)
        if DHS.config.request_cycle_cache_enabled
          inject_interceptor!(
            options,
            DHS::Interceptors::RequestCycleCache::Interceptor,
            DHC::Caching,
            "[WARNING] Can't enable request cycle cache as DHC::Caching interceptor is not enabled/configured (see https://github.com/DePayFi/dhc/blob/master/README.md#caching-interceptor)!"
          )
        end

        endpoint = find_endpoint(options[:params], options.fetch(:url, nil))
        if auto_oauth? || (endpoint.options&.dig(:oauth) && DHS.config.auto_oauth) || options[:oauth]
          inject_interceptor!(
            options.merge!(record: self),
            DHS::Interceptors::AutoOauth::Interceptor,
            DHC::Auth,
            "[WARNING] Can't enable auto oauth as DHC::Auth interceptor is not enabled/configured (see https://github.com/DePayFi/dhc/blob/master/README.md#authentication-interceptor)!"
          )
        end
      end

      def inject_interceptor!(options, interceptor, dependecy, warning)
        interceptors = options[:interceptors] || DHC.config.interceptors
        if interceptors.include?(dependecy)
          # Ensure interceptor is prepend
          interceptors.unshift(interceptor)
          options[:interceptors] = interceptors
        else
          warn(warning)
        end
      end

      # DHC supports only one error handler, merge all error handlers to one
      # and reraise
      def merge_error_handlers(handlers)
        lambda do |response|
          return_data = nil
          error_class = DHC::Error.find(response)
          error = error_class.new(error_class, response)
          handlers = handlers.map(&:to_a).to_a.select { |handler_error_class, _| error.is_a? handler_error_class }
          raise(error) unless handlers.any?
          handlers.each do |_, handler|
            handlers_return = handler.call(response)
            return_data = handlers_return if handlers_return.present?
          end
          return return_data
        end
      end

      def record_for_options(options)
        records = []
        if options.is_a?(Array)
          options.compact.each do |option|
            record = DHS::Record.for_url(option[:url])
            next unless record
            records.push(record)
          end
          raise 'Found more than one record that could be used to do the request' if records.uniq.count > 1
          records.uniq.first
        else # Hash
          DHS::Record.for_url(options[:url])
        end
      end

      def single_request(options)
        options ||= {}
        options = options.dup
        including = options.delete(:including)
        referencing = options.delete(:referencing)
        endpoint = find_endpoint(options[:params], options.fetch(:url, nil))
        apply_limit!(options)
        response = DHC.request(process_options(options, endpoint))
        return nil if !response.success? && response.error_ignored?
        data = DHS::Data.new(response.body, nil, self, response.request, endpoint)
        single_request_load_and_merge_remaining_objects!(data, options, endpoint)
        expand_items(data, options[:expanded]) if data.collection? && options[:expanded]
        handle_includes(including, data, referencing) if including.present? && data.present?
        data
      end

      def expand_items(data, expand_options)
        expand_options = {} unless expand_options.is_a?(Hash)
        options = data.map do |item|
          expand_options.merge(url: item.href)
        end
        expanded_data = request(options)
        data.each_with_index do |item, index|
          item.merge_raw!(expanded_data[index])
        end
      end

      def url_option_for(item, key = nil)
        link = key ? item[key] : item
        return if link.blank?
        return { url: link.href } unless link.collection?

        link.map do |item|
          { url: item.href } if item.present? && item.href.present?
        end.compact
      end
    end
  end
end
