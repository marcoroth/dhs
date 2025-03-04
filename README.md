DHS
===

DHS ia a Rails-Gem, providing an ActiveRecord like interface to access HTTP-JSON-Services from Rails Applications. Special features provided by this gem are: Multiple endpoint configuration per resource, active-record-like query-chains, scopes, error handling, relations, request cycle cache, batch processing, including linked resources (hypermedia), data maps (data accessing), nested-resource handling, ActiveModel like backend validation conversion, formbuilder-compatible, three types of pagination support, service configuration per resource, kaminari-support and much more.

DHS uses [DHC](//github.com/DePayFi/DHC) for advanced http requests.

## Quickstart

```
gem 'dhs'
```

```ruby
# config/initializers/dhc.rb

DHC.configure do |config|
  config.placeholder(:service, 'https://my.service.dev')
end
```

```ruby
# app/models/record.rb

class Record < DHS::Record

  endpoint '{+service}/records'
  endpoint '{+service}/records/{id}'

end
```

```ruby
# app/controllers/application_controller.rb

record = Record.find_by(email: 'somebody@mail.com')
record.review # "Lunch was great
```

## Installation/Startup checklist

- [x] Install DHS gem, preferably via `Gemfile`
- [x] Configure [DHC](https://github.com/DePayFi/dhc) via an `config/initializers/dhc.rb` (See: https://github.com/DePayFi/dhc#configuration)
- [x] Add `DHC::Caching` to `DHC.config.interceptors` to facilitate DHS' [Request Cycle Cache](#request-cycle-cache)
- [x] Store all DHS::Records in `app/models` for autoload/preload reasons
- [x] Request data from services via `DHS` from within your rails controllers

## Record

### Endpoints

> Endpoint, the entry point to a service, a process, or a queue or topic destination in service-oriented architecture

Start a record with configuring one or multiple endpoints.

```ruby
# app/models/record.rb

class Record < DHS::Record

  endpoint '{+service}/records'
  endpoint '{+service}/records/{id}'
  endpoint '{+service}/accociation/{accociation_id}/records'
  endpoint '{+service}/accociation/{accociation_id}/records/{id}'

end
```

You can also add request options to be used with configured endpoints:

```ruby
# app/models/record.rb

class Record < DHS::Record

  endpoint '{+service}/records', auth: { bearer: -> { access_token } }
  endpoint '{+service}/records/{id}', auth: { bearer: -> { access_token } }

end
```

-> Check [DHC](https://github.com/DePayFi/dhc) for more information about request options

#### Configure endpoint hosts

It's common practice to use different hosts accross different environments in a service-oriented architecture.

Use [DHC placeholders](https://github.com/DePayFi/dhc#configuring-placeholders) to configure different hosts per environment:

```ruby
# config/initializers/dhc.rb

DHC.configure do |config|
  config.placeholder(:search, ENV['SEARCH'])
end
```

```ruby
# app/models/record.rb

class Record < DHS::Record

  endpoint '{+search}/api/search.json'

end
```

**DON'T!**

Please DO NOT mix host placeholders with and endpoint's resource path, as otherwise DHS will not work properly.

```ruby
# config/initializers/dhc.rb

DHC.configure do |config|
  config.placeholder(:search, 'http://tel.search.ch/api/search.json')
end
```

```ruby
# app/models/record.rb

class Record < DHS::Record

  endpoint '{+search}'
  
end
```

#### Endpoint Priorities

DHS uses endpoint configurations to determine what endpoint to use when data is requested, in a similiar way, routes are identified in Rails to map requests to controllers.

If they are ambiguous, DHS will always use the first one found:

```ruby
# app/models/record.rb

class Record < DHS::Record

  endpoint '{+service}/records'
  endpoint '{+service}/bananas'

end
```

```ruby
# app/controllers/some_controller.rb

Record.fetch
```
```
GET https://service.example.com/records
```

**Be aware that, if you configure ambigious endpoints accross multiple classes, the order of things is not deteministic. Ambigious endpoints accross multiple classes need to be avoided.**

### Provider

Providers in DHS allow you to group shared endpoint options under a common provider.

```ruby
# app/models/provider/base_record.rb

module Provider
  class BaseRecord < DHS::Record
    provider params: { api_key: 123 }
  end
end
```

Now every record, part of that particular provider can inherit the provider's `BaseRecord`.

```ruby
# app/models/provider/account.rb

module Provider
  class Account < BaseRecord
    endpoint '{+host}/records'
    endpoint '{+host}/records/{id}'
  end
end
```

```ruby
# app/controllers/some_controller.rb

Provider::Account.find(1)
```
```
GET https://provider/records/1?api_key=123
```

And requests made via those provider records apply the common provider options.

### Record inheritance

You can inherit from previously defined records and also inherit endpoints that way:

```ruby
# app/models/base.rb

class Base < DHS::Record
  endpoint '{+service}/records/{id}'
end
```

```ruby
# app/models/record.rb

class Record < Base
end
```

```ruby
# app/controllers/some_controller.rb

Record.find(1)
```
```
GET https://service.example.com/records/1
```

### Find multiple records

#### fetch

In case you want to just fetch the records endpoint, without applying any further queries or want to handle pagination, you can simply call `fetch`:

```ruby
# app/controllers/some_controller.rb

records = Record.fetch

```
```
  GET https://service.example.com/records
```

#### where

You can query a service for records by using `where`:

```ruby
# app/controllers/some_controller.rb

Record.where(color: 'blue')

```
```
  GET https://service.example.com/records?color=blue
```

If the provided parameter – `color: 'blue'` in this case – is not part of the endpoint path, it will be added as query parameter.

```ruby
# app/controllers/some_controller.rb

Record.where(accociation_id: '12345')

```
```
GET https://service.example.com/accociation/12345/records
```

If the provided parameter – `accociation_id` in this case – is part of the endpoint path, it will be injected into the path.

You can also provide hrefs to fetch multiple records:

```ruby
# app/controllers/some_controller.rb

Record.where('https://service.example.com/accociation/12345/records')

```
```
GET https://service.example.com/accociation/12345/records
```


#### Reuse/Dry where statements: Use scopes

In order to reuse/dry where statements organize them in scopes:

```ruby
# app/models/record.rb

class Record < DHS::Record

  endpoint '{+service}/records'
  endpoint '{+service}/records/{id}'

  scope :blue, -> { where(color: 'blue') }
  scope :available, ->(state) { where(available: state) }

end
```

```ruby
# app/controllers/some_controller.rb

records = Record.blue.available(true)
```
```
GET https://service.example.com/records?color=blue&available=true
```

#### all

You can fetch all remote records by using `all`. Pagination will be performed automatically (See: [Record pagination](#record-pagination))

```ruby
# app/controllers/some_controller.rb

records = Record.all

```
```
  GET https://service.example.com/records?limit=100
  GET https://service.example.com/records?limit=100&offset=100
  GET https://service.example.com/records?limit=100&offset=200
```

```ruby
# app/controllers/some_controller.rb

records.size # 300

```

#### all with unpaginated endpoints

In case your record endpoints are not implementing any pagination, configure it to be `paginated: false`. Pagination will not be performed automatically in those cases:

```ruby
# app/models/record.rb

class Record < DHS::Record
  configuration paginated: false
end

```

```ruby
# app/controllers/some_controller.rb

records = Record.all

```
```
  GET https://service.example.com/records
```

#### Retrieve the amount of a collection of items: count vs. length

The different behavior of `count` and `length` is based on ActiveRecord's behavior.

`count` The total number of items available remotly via the provided endpoint/api, communicated via pagination meta data.

`length` The number of items already loaded from the endpoint/api and kept in memmory right now. In case of a paginated endpoint this can differ to what `count` returns, as it depends on how many pages have been loaded already.

### Find single records

#### find

`find` finds a unique record by unique identifier (usually `id` or `href`). If no record is found an error is raised.

```ruby
Record.find(123)
```
```
GET https://service.example.com/records/123
```

```ruby
Record.find('https://anotherservice.example.com/records/123')
```
```
GET https://anotherservice.example.com/records/123
```

`find` can also be used to find a single unique record with parameters:

```ruby
Record.find(another_identifier: 456)
```
```
GET https://service.example.com/records?another_identifier=456
```

You can also fetch multiple records by `id` in parallel:

```ruby
Record.find(1, 2, 3)
```
```
# In parallel:
  GET https://service.example.com/records/1
  GET https://service.example.com/records/2
  GET https://service.example.com/records/3
```

#### find_by

`find_by` finds the first record matching the specified conditions. If no record is found, `nil` is returned.

`find_by!` raises `DHC::NotFound` if nothing was found.

```ruby
Record.find_by(color: 'blue')
```
```
GET https://service.example.com/records?color=blue
```

#### first

`first` is an alias for finding the first record without parameters. If no record is found, `nil` is returned.

`first!` raises `DHC::NotFound` if nothing was found.

```ruby
Record.first
```
```
GET https://service.example.com/records?limit=1
```

`first` can also be used with options:

```ruby
Record.first(params: { color: :blue })
```
```
GET https://service.example.com/records?color=blue&limit=1
```

#### last

`last` is an alias for finding the last record without parameters. If no record is found, `nil` is returned.

`last!` raises `DHC::NotFound` if nothing was found.

```ruby
Record.last
```

`last` can also be used with options:

```ruby
Record.last(params: { color: :blue })
```

### Work with retrieved data

After fetching [single](#find-single-records) or [multiple](#find-multiple-records) records you can navigate the received data with ease:

```ruby
records = Record.where(color: 'blue')
records.length # 4
records.count # 400
record = records.first
record.type # 'Business'
record[:type] # 'Business'
record['type'] # 'Business'
```

#### Automatic detection/conversion of collections

How to configure endpoints for automatic collection detection?

DHS detects automatically if the responded data is a single business object or a set of business objects (collection).

Conventionally, when the responds contains an `items` key `{ items: [] }` it's treated as a collection, but also if the responds contains a plain raw array: `[{ href: '' }]` it's also treated as a collection.

If you need to configure the attribute of the response providing the collection, configure `items_key` as explained here: [Determine collections from the response body](#determine-collections-from-the-response-body)

#### Map complex data for easy access

To influence how data is accessed, simply create methods inside your Record to access complex data structures:

```ruby
# app/models/record.rb

class Record < DHS::Record

  endpoint '{+service}/records'

  def name
    dig(:addresses, :first, :business, :identities, :first, :name)
  end
end
```

#### Access and identify nested records

Nested records, in nested data, are automatically casted to the correct Record class, when they provide an `href` and that `href` matches any defined endpoint of any defined Record:

```ruby
# app/models/place.rb

class Place < DHS::Record
  endpoint '{+service}/places'
  endpoint '{+service}/places/{id}'

  def name
    dig(:addresses, :first, :business, :identities, :first, :name)
  end
end
```

```ruby
# app/models/favorite.rb

class Favorite < DHS::Record
  endpoint '{+service}/favorites'
  endpoint '{+service}/favorites/{id}'
end
```

```ruby
# app/controllers/some_controller.rb

favorite = Favorite.includes(:place).find(123)
favorite.place.name # depay.fi AG
```
```
GET https://service.example.com/favorites/123

{... place: { href: 'https://service.example.com/places/456' }}

GET https://service.example.com/places/456
```

If automatic detection of nested records does not work, make sure your Records are stored in `app/models`! See: [Insallation/Startup checklist](#installationstartup-checklist)

##### Relations / Associations

Typically nested data is automatically casted when accessed (See: [Access and identify nested records](#access-and-identify-nested-records)), but sometimes API's don't provide dedicated endpoints to retrieve these records.
In those cases, those records are only available through other records and don't have an `href` on their own and can't be casted automatically, when accessed. 

To be able to implement Record-specific logic for those nested records, you can define relations/associations.

###### has_many

```ruby
# app/models/location.rb

class Location < DHS::Record

  endpoint '{+service}/locations/{id}'

  has_many :listings

end
```

```ruby
# app/models/listing.rb

class Listing < DHS::Record

  def supported?
    type == 'SUPPORTED'
  end
end
```

```ruby
# app/controllers/some_controller.rb

Location.find(1).listings.first.supported? # true
```
```
GET https://service.example.com/locations/1
{... listings: [{ type: 'SUPPORTED' }] }
```

`class_name`: Specify the class name of the relation. Use it only if that name can't be inferred from the relation name. So has_many :photos will by default be linked to the Photo class, but if the real class name is e.g. CustomPhoto or namespaced Custom::Photo, you'll have to specify it with this option.

```ruby
# app/models/custom/location.rb

module Custom
  class Location < DHS::Record
    endpoint '{+service}/locations'
    endpoint '{+service}/locations/{id}'
    
    has_many :photos, class_name: 'Custom::Photo'
  end
end
```

```ruby
# app/models/custom/photo.rb

module Custom
  class Photo < DHS::Record
  end
end
```

###### has_one

```ruby
# app/models/transaction.rb

class Transaction < DHS::Record

  endpoint '{+service}/transaction/{id}'

  has_one :user
end
```

```ruby
# app/models/user.rb

class User < DHS::Record

  def email
    self[:email_address]
  end
end
```

```ruby
# app/controllers/some_controller.rb

Transaction.find(1).user.email_address # steve@depay.fi
```
```
GET https://service.example.com/transaction/1
{... user: { email_address: 'steve@depay.fi' } }
```

`class_name`: Specify the class name of the relation. Use it only if that name can't be inferred from the relation name. So has_many :photos will by default be linked to the Photo class, but if the real class name is e.g. CustomPhoto or namespaced Custom::Photo, you'll have to specify it with this option.

```ruby
# app/models/custom/location.rb

module Custom
  class Location < DHS::Record
    endpoint '{+service}/locations'
    endpoint '{+service}/locations/{id}'
    
    has_one :photo, class_name: 'Custom::Photo'
  end
end
```

```ruby
# app/models/custom/photo.rb

module Custom
  class Photo < DHS::Record
  end
end
```

#### Unwrap nested items from the response body

If the actual item data is mixed with meta data in the response body, DHS allows you to configure a record in a way to automatically unwrap items from within nested response data.

`item_key` is used to unwrap the actual object from within the response body.

```ruby
# app/models/location.rb

class Location < DHS::Record
  configuration item_key: [:response, :location]
end
```

```ruby
# app/controllers/some_controller.rb

location = Location.find(123)
location.id # 123
```
```
GET https://service.example.com/locations/123
{... response: { location: { id: 123 } } }
```

#### Determine collections from the response body

`items_key` key used to determine the collection of items of the current page (e.g. `docs`, `items`, etc.), defaults to 'items':

```ruby
# app/models/search.rb

class Search < DHS::Record
  configuration items_key: :docs
end
```

```ruby
# app/controllers/some_controller.rb

search_result = Search.where(q: 'Starbucks')
search_result.first.address # Bahnhofstrasse 5, 8000 Zürich
```
```
GET https://service.example.com/search?q=Starbucks
{... docs: [... {...  address: 'Bahnhofstrasse 5, 8000 Zürich' }] }
```

#### Load additional data based on retrieved data

In order to load linked data from already retrieved data, you can use `load!` (or `reload!`).

```ruby
# app/controllers/some_controller.rb

record = Record.find(1)
record.associated_thing.load!
```
```
GET https://things/4
{ name: "Steve" }
```
```ruby
# app/controllers/some_controller.rb
record.associated_thing.name # Steve

record.associated_thing.load! # Does NOT create another request, as it is already loaded
record.associated_thing.reload! # Does request the data again from remote

```
```
GET https://things/4
{ name: "Steve" }
```

### Chain complex queries

> [Method chaining](https://en.wikipedia.org/wiki/Method_chaining), also known as named parameter idiom, is a common syntax for invoking multiple method calls in object-oriented programming languages. Each method returns an object, allowing the calls to be chained together without requiring variables to store the intermediate results

In order to simplify and enhance preparing complex queries for performing single or multiple requests, DHS implements query chains to find single or multiple records. 

DHS query chains do [lazy evaluation](https://de.wikipedia.org/wiki/Lazy_Evaluation) to only perform as many requests as needed, when the data to be retrieved is actually needed.

Any method, accessing the content of the data to be retrieved, is resolving the chain in place – like `.each`, `.first`, `.some_attribute_name`. Nevertheless, if you just want to resolve the chain in place, and nothing else, `fetch` should be the method of your choice:

```ruby
# app/controllers/some_controller.rb

Record.where(color: 'blue').fetch
```

#### Chain where queries

```ruby
# app/controllers/some_controller.rb

records = Record.where(color: 'blue')
[...]
records.where(available: true).each do |record|
  [...]
end
```
```
  GET https://service.example.com/records?color=blue&available=true
```

In case you wan't to check/debug the current values for where in the chain, you can use `where_values_hash`:

```ruby
records.where_values_hash

# {color: 'blue', available: true}
```

#### Expand plain collections of links: expanded

Some endpoints could respond only with a plain list of links and without any expanded data, like search results.

Use `expanded` to have DHS expand that data, by performing necessary requests in parallel:

```ruby
# app/controllers/some_controller.rb

Search.where(what: 'Cafe').expanded
```
```
GET https://service.example.com/search?what=Cafe
{...
  "items" : [
    {"href": "https://service.example.com/records/1"},
    {"href": "https://service.example.com/records/2"},
    {"href": "https://service.example.com/records/3"}
  ]
}

In parallel:
  > GET https://service.example.com/records/1
  < {... name: 'Cafe Einstein'}
  > GET https://service.example.com/records/2
  < {... name: 'Starbucks'}
  > GET https://service.example.com/records/3
  < {... name: 'Plaza Cafe'}

{
  ...
  "items" : [
    {
      "href": "https://service.example.com/records/1",
      "name": 'Cafe Einstein',
      ...
    },
    {
      "href": "https://service.example.com/records/2",
      "name": 'Starbucks',
      ...
    },
    {
      "href": "https://service.example.com/records/3",
      "name": 'Plaza Cafe',
      ...
    }
  ]
}
```

You can also apply request options to `expanded`. Those options will be used to perform the additional requests to expand the data:

```ruby
# app/controllers/some_controller.rb

Search.where(what: 'Cafe').expanded(auth: { bearer: access_token })
```

#### Error handling with chains

One benefit of chains is lazy evaluation. But that also means they only get resolved when data is accessed. This makes it hard to catch errors with normal `rescue` blocks:

```ruby
# app/controllers/some_controller.rb

def show
  @records = Record.where(color: blue) # returns a chain, nothing is resolved, no http requests are performed
rescue => e
  # never ending up here, because the http requests are actually performed in the view, when the query chain is resolved
end
```

```ruby
# app/views/some/view.haml

= @records.each do |record| # .each resolves the query chain, leads to http requests beeing performed, which might raises an exception
  = record.name
```

To simplify error handling with chains, you can also chain error handlers to be resolved, as part of the chain.

If you need to render some different view in Rails based on an DHS error raised during rendering the view, please proceed as following:

```ruby
# app/controllers/some_controller.rb

def show
  @records = Record
    .rescue(DHC::Error, ->(error){ rescue_from(error) })
    .where(color: 'blue')
  render 'show'
  render_error if @error
end

private

def rescue_from(error)
  @error = error
  nil
end

def render_error
  self.response_body = nil # required to not raise AbstractController::DoubleRenderError
  render 'error'
end
```
```
> GET https://service.example.com/records?color=blue
< 406
```

In case no matching error handler is found the error gets re-raised.

-> Read more about [DHC error types/classes](https://github.com/DePayFi/dhc#exceptions)

If you want to inject values for the failing records, that might not have been found, you can inject values for them with error handlers:

```ruby
# app/controllers/some_controller.rb

data = Record
  .rescue(DHC::Unauthorized, ->(response) { Record.new(name: 'unknown') })
  .find(1, 2, 3)

data[1].name # 'unknown'
```
```
In parallel:
  > GET https://service.example.com/records/1
  < 200
  > GET https://service.example.com/records/2
  < 400
  > GET https://service.example.com/records/3
  < 200
```

-> Read more about [DHC error types/classes](https://github.com/DePayFi/dhc#exceptions)

**If an error handler returns `nil` an empty DHS::Record is returned, not `nil`!**

In case you want to ignore errors and continue working with `nil` in those cases,
please use `ignore`:

```ruby
# app/controllers/some_controller.rb

record = Record.ignore(DHC::NotFound).find_by(color: 'blue')

record # nil
```

#### Resolve chains: fetch

In case you need to resolve a query chain in place, use `fetch`:

```ruby
# app/controllers/some_controller.rb

records = Record.where(color: 'blue').fetch
```

#### Add request options to a query chain: options

You can apply options to the request chain. Those options will be forwarded to the request perfomed by the chain/query:

```ruby
# app/controllers/some_controller.rb

options = { auth: { bearer: '123456' } } # authenticated with OAuth token

```

```ruby
# app/controllers/some_controller.rb

AuthenticatedRecord = Record.options(options)

```

```ruby
# app/controllers/some_controller.rb

blue_records = AuthenticatedRecord.where(color: 'blue')

```
```
GET https://service.example.com/records?color=blue { headers: { 'Authentication': 'Bearer 123456' } }
```

```ruby
# app/controllers/some_controller.rb

AuthenticatedRecord.create(color: 'red')

```
```
POST https://service.example.com/records { body: '{ color: "red" }' }, headers: { 'Authentication': 'Bearer 123456' } }
```

```ruby
# app/controllers/some_controller.rb

record = AuthenticatedRecord.find(123)

```
```
GET https://service.example.com/records/123 { headers: { 'Authentication': 'Bearer 123456' } }
```

```ruby
# app/controllers/some_controller.rb

authenticated_record = record.options(options) # starting a new chain based on the found record

```

```ruby
# app/controllers/some_controller.rb

authenticated_record.valid?

```
```
POST https://service.example.com/records/validate { body: '{...}', headers: { 'Authentication': 'Bearer 123456' } }
```

```ruby
# app/controllers/some_controller.rb

authenticated_record.save
```
```
POST https://service.example.com/records { body: '{...}', headers: { 'Authentication': 'Bearer 123456' } }
```

```ruby
# app/controllers/some_controller.rb

authenticated_record.destroy

```
```
DELETE https://service.example.com/records/123 { headers: { 'Authentication': 'Bearer 123456' } }
```

```ruby
# app/controllers/some_controller.rb

authenticated_record.update(name: 'Steve')

```
```
POST https://service.example.com/records/123 { body: '{...}', headers: { 'Authentication': 'Bearer 123456' } }
```

#### Control pagination within a query chain

`page` sets the page that you want to request.

`per` sets the amount of items requested per page.

`limit` is an alias for `per`. **But without providing arguments, it resolves the query and provides the current response limit per page**

```ruby
# app/controllers/some_controller.rb

Record.page(3).per(20).where(color: 'blue')

```
```
GET https://service.example.com/records?offset=40&limit=20&color=blue
```

```ruby
# app/controllers/some_controller.rb

Record.page(3).per(20).where(color: 'blue')

```
```
GET https://service.example.com/records?offset=40&limit=20&color=blue
```

The applied pagination strategy depends on whats configured for the particular record: See [Record pagination](#record-pagination)

### Record pagination

You can configure pagination on a per record base. 
DHS differentiates between the [pagination strategy](#pagination-strategy) (how items/pages are navigated and calculated) and [pagination keys](#pagination-keys) (how stuff is named and accessed).

#### Pagination strategy

##### Pagination strategy: offset (default)

The offset pagination strategy is DHS's default pagination strategy, so nothing needs to be (re-)configured.

The `offset` pagination strategy starts with 0 and offsets by the amount of items, thay you've already recived – typically `limit`.

```ruby
# app/models/record.rb

class Search < DHS::Record
  endpoint '{+service}/search'
end
```

```ruby
# app/controllers/some_controller.rb

Record.all

```
```
GET https://service.example.com/records?limit=100
{
  items: [{...}, ...],
  total: 300,
  limit: 100,
  offset: 0
}
In parallel:
  GET https://service.example.com/records?limit=100&offset=100
  GET https://service.example.com/records?limit=100&offset=200
```

##### Pagination strategy: page

In comparison to the `offset` strategy, the `page` strategy just increases by 1 (page) and sends the next batch of items for the next page.

```ruby
# app/models/record.rb

class Search < DHS::Record
  configuration pagination_strategy: 'page', pagination_key: 'page'

  endpoint '{+service}/search'
end
```

```ruby
# app/controllers/some_controller.rb

Record.all

```
```
GET https://service.example.com/records?limit=100
{
  items: [{...}, ...],
  total: 300,
  limit: 100,
  page: 1
}
In parallel:
  GET https://service.example.com/records?limit=100&page=2
  GET https://service.example.com/records?limit=100&page=3
```

##### Pagination strategy: total_pages

The `total_pages` strategy is based on the `page` strategy with the only difference
that the responding api provides `total_pages` over `total_items`.

```ruby
# app/models/transaction.rb

class Transaction < DHS::Record
  configuration pagination_strategy: 'total_pages', pagination_key: 'page', total_key: 'total_pages'

  endpoint '{+service}/transactions'
end
```

```ruby
# app/controllers/some_controller.rb

Record.all

```
```
GET https://service.example.com/transactions?limit=100
{
  items: [{...}, ...],
  total_pages: 3,
  limit: 100,
  page: 1
}
In parallel:
  GET https://service.example.com/records?limit=100&page=2
  GET https://service.example.com/records?limit=100&page=3
```


##### Pagination strategy: start

In comparison to the `offset` strategy, the `start` strategy indicates with which item the current page starts. 
Typically it starts with 1 and if you get 100 items per page, the next start is 101.

```ruby
# app/models/record.rb

class Search < DHS::Record
  configuration pagination_strategy: 'start', pagination_key: 'startAt'

  endpoint '{+service}/search'
end
```

```ruby
# app/controllers/some_controller.rb

Record.all

```
```
GET https://service.example.com/records?limit=100
{
  items: [{...}, ...],
  total: 300,
  limit: 100,
  page: 1
}
In parallel:
  GET https://service.example.com/records?limit=100&startAt=101
  GET https://service.example.com/records?limit=100&startAt=201
```

##### Pagination strategy: link

The `link` strategy continuously follows in-response embedded links to following pages until the last page is reached (indicated by no more `next` link).

*WARNING*

Loading all pages from a resource paginated with links only can result in very poor performance, as pages can only be loaded sequentially!

```ruby
# app/models/record.rb

class Search < DHS::Record
  configuration pagination_strategy: 'link'

  endpoint '{+service}/search'
end
```

```ruby
# app/controllers/some_controller.rb

Record.all

```
```
GET https://service.example.com/records?limit=100
{
  items: [{...}, ...],
  limit: 100,
  next: {
    href: 'https://service.example.com/records?from_record_id=p62qM5p0NK_qryO52Ze-eg&limit=100'
  }
}
Sequentially:
  GET https://service.example.com/records?from_record_id=p62qM5p0NK_qryO52Ze-eg&limit=100
  GET https://service.example.com/records?from_record_id=xcaoXBmuMyFFEcFDSgNgDQ&limit=100
```

#### Pagination keys

##### limit_key

`limit_key` sets the key used to indicate how many items you want to retrieve per page e.g. `size`, `limit`, etc.
In case the `limit_key` parameter differs for how it needs to be requested from how it's provided in the reponse, use `body` and `parameter` subkeys.

```ruby
# app/models/record.rb

class Record < DHS::Record
  configuration limit_key: { body: [:pagination, :max], parameter: :max }

  endpoint '{+service}/records'
end
```

```ruby
# app/controllers/some_controller.rb

records = Record.where(color: 'blue')
records.limit # 20
```
```
GET https://service.example.com/records?color=blue&max=100
{ ...
  items: [...],
  pagination: { max: 20 }
}
```

##### pagination_key

`pagination_key` defines which key to use to paginate a page (e.g. `offset`, `page`, `startAt` etc.).
In case the `limit_key` parameter differs for how it needs to be requested from how it's provided in the reponse, use `body` and `parameter` subkeys.

```ruby
# app/models/record.rb

class Record < DHS::Record
  configuration pagination_key: { body: [:pagination, :page], parameter: :page }, pagination_strategy: :page

  endpoint '{+service}/records'
end
```

```ruby
# app/controllers/some_controller.rb

records = Record.where(color: 'blue').all
records.length # 300
```
```
GET https://service.example.com/records?color=blue&limit=100
{... pagination: { page: 1 } }
In parallel:
  GET https://service.example.com/records?color=blue&limit=100&page=2
  {... pagination: { page: 2 } }
  GET https://service.example.com/records?color=blue&limit=100&page=3
  {... pagination: { page: 3 } }
```

##### total_key

`total_key` defines which key to user for pagination to describe the total amount of remote items (e.g. `total`, `totalResults`, etc.).

```ruby
# app/models/record.rb

class Record < DHS::Record
  configuration total_key: [:pagination, :total]

  endpoint '{+service}/records'
end
```

```ruby
# app/controllers/some_controller.rb

records = Record.where(color: 'blue').fetch
records.length # 100
records.count # 300
```
```
GET https://service.example.com/records?color=blue&limit=100
{... pagination: { total: 300 } }
```

#### Pagination links

##### next?

`next?` Tells you if there is a next link or not.

```ruby
# app/controllers/some_controller.rb

@records = Record.where(color: 'blue').fetch
```
```
GET https://service.example.com/records?color=blue&limit=100
{... items: [...], next: 'https://service.example.com/records?color=blue&limit=100&offset=100' }
```

```ruby
# app/views/some_view.haml

- if @records.next?
  = render partial: 'next_arrow'
```

##### previous?

`previous?` Tells you if there is a previous link or not.

```ruby
# app/controllers/some_controller.rb

@records = Record.where(color: 'blue').fetch
```
```
GET https://service.example.com/records?color=blue&limit=100
{... items: [...], previous: 'https://service.example.com/records?color=blue&limit=100&offset=100' }
```

```ruby
# app/views/some_view.haml

- if @records.previous?
  = render partial: 'previous_arrow'
```

#### Kaminari support (limited)

DHS implements an interface that makes it partially working with Kaminari.

The kaminari’s page parameter is in params[:page]. For example, you can use kaminari to render paginations based on DHS Records. Typically, your code will look like this:

```ruby
# controller
@items = Record.page(params[:page]).per(100)
```

```ruby
# view
= paginate @items
```

### Build, create and update records

#### Create new records

##### create

`create` will return the object in memory if persisting fails, providing validation errors in `.errors` (See [record validation](#record-validation)).

`create!` instead will raise an exception.

`create` always builds the data of the local object first, before it tries to sync with an endpoint. So even if persisting fails, the local object is build.

```ruby
# app/controllers/some_controller.rb

record = Record.create(
  text: 'Hello world'
)

```
```
POST https://service.example.com/records { body: "{ 'text' : 'Hello world' }" }
```

-> See [record validation](#record-validation) for how to handle validation errors when creating records.

###### Unwrap nested data when creation response nests created record data

`item_created_key` key used to merge record data thats nested in the creation response body:

```ruby
# app/models/location.rb

class Location < DHS::Record

  configuration item_created_key: [:response, :location]

end
```

```ruby
# app/controllers/some_controller.rb

location.create(lat: '47.3920152', long: '8.5127981')
location.address # Förrlibuckstrasse 62, 8005 Zürich
```
```
POST https://service.example.com/locations { body: "{ 'lat': '47.3920152', long: '8.5127981' }" }
{... { response: { location: {... address: 'Förrlibuckstrasse 62, 8005 Zürich' } } } } 
```

###### Create records through associations: Nested sub resources

```ruby
# app/models/restaurant.rb

class Restaurant < DHS::Record
  endpoint '{+service}/restaurants/{id}'
end

```

```ruby
# app/models/feedback.rb

class Feedback < DHS::Record
  endpoint '{+service}/restaurants/{restaurant_id}/feedbacks'
end

```

```ruby
# app/controllers/some_controller.rb

restaurant = Restaurant.find(1)
```
```
GET https://service.example.com/restaurants/1
{... reviews: { href: 'https://service.example.com/restaurants/1/reviews' }}
```

```ruby
# app/controllers/some_controller.rb

restaurant.reviews.create(
  text: 'Simply awesome!'
)
```
```
POST https://service.example.com/restaurants/1/reviews { body: "{ 'text': 'Simply awesome!' }" }
```

#### Start building new records

With `new` or `build` you can start building new records from scratch, which can be persisted with `save`:

```ruby
# app/controllers/some_controller.rb

record = Record.new # or Record.build
record.name = 'Starbucks'
record.save
```
```
POST https://service.example.com/records { body: "{ 'name' : 'Starbucks' }" }
```

#### Change/Update existing records

##### save

`save` persist the whole object in it's current state. 

`save` will return `false` if persisting fails. `save!` instead will raise an exception.

```ruby
# app/controllers/some_controller.rb

record = Record.find('1z-5r1fkaj')

```
```
GET https://service.example.com/records/1z-5r1fkaj
{ name: 'Starbucks', recommended: null }
```

```ruby
# app/controllers/some_controller.rb

record.recommended = true
record.save

```
```
POST https://service.example.com/records/1z-5r1fkaj { body: "{ 'name': 'Starbucks', 'recommended': true }" }
```

-> See [record validation](#record-validation) for how to handle validation errors when updating records.

##### update

###### Directly via Record

```ruby
# app/controllers/some_controller.rb

Record.update(id: '1z-5r1fkaj', name: 'Steve')

```
```
GET https://service.example.com/records/1z-5r1fkaj
{ name: 'Steve' }
```

###### per Instance

`update` persists the whole object after new parameters are applied through arguments.

`update` will return false if persisting fails. `update!` instead will raise an exception.

`update` always updates the data of the local object first, before it tries to sync with an endpoint. So even if persisting fails, the local object is updated.

```ruby
# app/controllers/some_controller.rb

record = Record.find('1z-5r1fkaj')

```
```
GET https://service.example.com/records/1z-5r1fkaj
{ name: 'Starbucks', recommended: null }
```

```ruby
# app/controllers/some_controller.rb

record.update(recommended: true)

```
```
POST https://service.example.com/records/1z-5r1fkaj { body: "{ 'name': 'Starbucks', 'recommended': true }" }
```

-> See [record validation](#record-validation) for how to handle validation errors when updating records.

You can use `update` and the end of query-chains:

```ruby
# app/controllers/some_controller.rb

record.options(method: :put).update(recommended: true)

```

You can also pass explicit request options to `update`, by passing two explicit hashes:

```ruby
# app/controllers/some_controller.rb

record.update({ recommended: true }, { method: 'put' })

```

##### partial_update

`partial_update` updates just the provided parameters.

`partial_update` will return false if persisting fails. `partial_update!` instead will raise an exception.

`partial_update` always updates the data of the local object first, before it tries to sync with an endpoint. So even if persisting fails, the local object is updated.

```ruby
# app/controllers/some_controller.rb

record = Record.find('1z-5r1fkaj')

```
```
GET https://service.example.com/records/1z-5r1fkaj
{ name: 'Starbucks', recommended: null }
```

```ruby
# app/controllers/some_controller.rb

record.partial_update(recommended: true)

```
```
POST https://service.example.com/records/1z-5r1fkaj { body: "{ 'recommended': true }" }
```

-> See [record validation](#record-validation) for how to handle validation errors when updating records.

You can use `partial_update` at the end of query-chains:

```ruby
# app/controllers/some_controller.rb

record.options(method: :put).partial_update(recommended: true)

```

You can also pass explicit request options to `partial_update`, by passing two explicit hashes:

```ruby
# app/controllers/some_controller.rb

record.partial_update({ recommended: true }, { method: 'put' })

```

#### Endpoint url parameter injection during record creation/change

DHS injects parameters provided to `create`, `update`, `partial_update`, `save` etc. into an endpoint's URL when matching:

```ruby
# app/models/feedback.rb

class Feedback << DHS::Record
  endpoint '{+service}/records/{record_id}/feedbacks'
end
```

```ruby
# app/controllers/some_controller.rb

Feedback.create(record_id: 51232, text: 'Great Restaurant!')
```
```
POST https://service.example.com/records/51232/feedbacks { body: "{ 'text' : 'Great Restaurant!' }" }
```

#### Record validation

In order to validate records before persisting them, you can use the `valid?` (`validate` alias) method.

It's **not recommended** to validate records anywhere, including application side validation via `ActiveModel::Validations`, except, if you validate them via the same endpoint/service, that also creates them.

The specific endpoint has to support validations without persistence. An endpoint has to be enabled (opt-in) in your record configurations:

```ruby
# app/models/user.rb

class User < DHS::Record

  endpoint '{+service}/users', validates: { params: { persist: false } }

end
```

```ruby
# app/controllers/some_controller.rb

user = User.build(email: 'i\'m not an email address')

unless user.valid?
  @errors = user.errors
  render 'new' and return
end
```
```
POST https://service.example.com/users?persist=false { body: '{ "email" : "i'm not an email address"}' }
{ 
  "field_errors": [{
    "path": ["email"],
    "code": "WRONG_FORMAT",
    "message": "The property value's format is incorrect."
  }],
  "message": "Email must have the correct format."
}
```

The functionalities of `DHS::Errors` pretty much follow those of `ActiveModel::Validation`:

```ruby
# app/views/some_view.haml

@errors.any? # true
@errors.include?(:email) # true
@errors[:email] # ['WRONG_FORMAT']
@errors.messages # {:email=>["Translated error message that this value has the wrong format"]}
@errors.codes # {:email=>["WRONG_FORMAT"]}
@errors.message # Email must have the correct format."
```

##### Configure record validations

The parameters passed to the `validates` endpoint option are used to perform record validations:

```ruby
# app/models/user.rb

class User < DHS::Record

  endpoint '{+service}/users', validates: { params: { persist: false } }  # will add ?persist=false to the request
  endpoint '{+service}/users', validates: { params: { publish: false } }  # will add ?publish=false to the request
  endpoint '{+service}/users', validates: { params: { validates: true } } # will add ?validates=true to the request
  endpoint '{+service}/users', validates: { path: 'validate' }            # will perform a validation via ...users/validate

end
```

##### HTTP Status Codes for validation errors

The HTTP status code received from the endpoint when performing validations on a record, is available through the errors object:

```ruby
# app/controllers/some_controller.rb

record.save
record.errors.status_code # 400
```

##### Reset validation errors

Clear the error messages like:

```ruby
# app/controllers/some_controller.rb

record.errors.clear
```

##### Add validation errors

In case you want to add application side validation errors, even though it's not recommended, do it as following:

```ruby
user.errors.add(:name, 'WRONG_FORMAT')
```

##### Validation errors for nested data

If you work with complex data structures, you sometimes need to have validation errors delegated/scoped to nested data.

This features makes `DHS::Record`s compatible with how Rails or Simpleform renders/builds forms and especially error messages:

```ruby
# app/controllers/some_controller.rb

unless @customer.save
  @errors = @customer.errors
end
```
```
POST https://service.example.com/customers { body: "{ 'address' : { 'street': 'invalid', housenumber: '' } }" }
{ 
  "field_errors": [{
    "path": ["address", "street"],
    "code": "REQUIRED_PROPERTY_VALUE_INCORRECT",
    "message": "The property value is incorrect."
  },{
    "path": ["address", "housenumber"],
    "code": "REQUIRED_PROPERTY_VALUE",
    "message": "The property value is required."
  }],
  "message": "Some data is invalid."
}
```

```ruby
# app/views/some_view.haml

= form_for @customer, as: :customer do |customer_form|

  = fields_for 'customer[:address]', @customer.address, do |address_form|

    = fields_for 'customer[:address][:street]', @customer.address.street, do |street_form|

      = street_form.input :name
      = street_form.input :house_number
```

This would render nested forms and would also render nested form errors for nested data structures.

You can also access those nested errors like:

```ruby
@customer.address.errors
@customer.address.street.errors
```

##### Translation of validation errors

If a translation exists for one of the following translation keys, DHS will provide a translated error (also in the following order) rather than the plain error message/code, when building forms or accessing `@errors.messages`:

```ruby
dhs.errors.records.<record_name>.attributes.<attribute_name>.<error_code>
e.g. dhs.errors.records.customer.attributes.name.unsupported_property_value

dhs.errors.records.<record_name>.<error_code>
e.g. dhs.errors.records.customer.unsupported_property_value

dhs.errors.messages.<error_code>
e.g. dhs.errors.messages.unsupported_property_value

dhs.errors.attributes.<attribute_name>.<error_code>
e.g. dhs.errors.attributes.name.unsupported_property_value

dhs.errors.fallback_message

dhs.errors.records.<record_name>.attributes.<collection>.<attribute_name>.<error_code>
e.g. dhs.errors.records.appointment_proposal.attributes.appointments.date_time.date_property_not_in_future
```

##### Validation error types: errors vs. warnings

###### Persistance failed: errors

If an endpoint returns errors in the response body, that is enough to interpret it as: persistance failed.
The response status code in this scenario is neglected.

###### Persistance succeeded: warnings

In some cases, you need non blocking meta information about potential problems with the created record, so called warnings.

If the API endpoint implements warnings, returned when validating, they are provided just as `errors` (same interface and methods) through the `warnings` attribute:

```ruby
# app/controllres/some_controller.rb

@presence = Presence.options(params: { synchronize: false }).create(
  place: { href: 'http://storage/places/1' }
)
```
```
POST https://service.example.com/presences { body: '{ "place": { "href": "http://storage/places/1" } }' }
{
    field_warnings: [{
      code: 'WILL_BE_RESIZED',
      path: ['place', 'photos', 0],
      message: 'This photo is too small and will be resized.'
    }
  }
```

```ruby

presence.warnings.any? # true
presence.place.photos[0].warnings.messages.first # 'This photo is too small and will be resized.'

```

##### Using `ActiveModel::Validations` none the less

If you are using `ActiveModel::Validations`, even though it's not recommended, and you add errors to the DHS::Record instance, then those errors will be overwritten by the errors from `ActiveModel::Validations` when using `save`  or `valid?`. 

So in essence, mixing `ActiveModel::Validations` and DHS built-in validations (via endpoints), is not compatible, yet.

[Open issue](https://github.com/DePayFi/dhs/issues/159)

#### Use form_helper to create and update records

Rails `form_for` view-helper can be used in combination with instances of `DHS::Record`s to autogenerate forms:

```ruby
<%= form_for(@instance, url: '/create') do |f| %>
  <%= f.text_field :name %>
  <%= f.text_area :text %>
  <%= f.submit "Create" %>
<% end %>
```

### Destroy records

`destroy`  deletes a record.

```ruby
# app/controllers/some_controller.rb

record = Record.find('1z-5r1fkaj')
```
```
GET https://service.example.com/records/1z-5r1fkaj
```

```ruby
# app/controllers/some_controller.rb

record.destroy
```
```
DELETE https://service.example.com/records/1z-5r1fkaj
```

You can also destroy records directly without fetching them first:

```ruby
# app/controllers/some_controller.rb

destroyed_record = Record.destroy('1z-5r1fkaj')
```
```
DELETE https://service.example.com/records/1z-5r1fkaj
```

or with parameters:

```ruby
# app/controllers/some_controller.rb

destroyed_records = Record.destroy(name: 'Steve')
```
```
DELETE https://service.example.com/records?name='Steve'
```

### Record getters and setters

Sometimes it is neccessary to implement custom getters and setters and convert data to a processable (endpoint) format behind the scenes.

#### Record setters

You can define setter methods in `DHS::Record`s that will be used by initializers (`new`) and setter methods, that convert data provided, before storing it in the record and persisting it with a remote endpoint:

```ruby
# app/models/user.rb

class Feedback < DHS::Record

  def ratings=(values)
    super(
      values.map { |k, v| { name: k, value: v } }
    )
  end
end
```

```ruby
# app/controllers/some_controller.rb

record = Record.new(ratings: { quality: 3 })
record.ratings # [{ :name=>:quality, :value=>3 }]
```

Setting attributes with other names:

```ruby
# app/models/booking.rb

class Booking < DHS::Record

  def appointments_attributes=(values)
    self.appointments = values.map { |appointment| appointment[:id] }
  end
end
```

or 

```ruby
# app/models/booking.rb

class Booking < DHS::Record

  def appointments_attributes=(values)
    self[:appointments] = values.map { |appointment| appointment[:id] }
  end
end
```

```ruby
# app/controllers/some_controller.rb

booking.update(params)
```

#### Record getters

If you implement accompanying getter methods, the whole data conversion would be internal only:

```ruby
# app/models/user.rb

class Feedback < DHS::Record

  def ratings=(values)
    super(
      values.map { |k, v| { name: k, value: v } }
    )
  end

  def ratings
    super.map { |r| [r[:name], r[:value]] }]
  end
end
```

```ruby
# app/controllers/some_controller.rb

record = Record.new(ratings: { quality: 3 })
record.ratings # {:quality=>3}
```

### Include linked resources (hyperlinks and hypermedia)

In a service-oriented architecture using [hyperlinks](https://en.wikipedia.org/wiki/Hyperlink)/[hypermedia](https://en.wikipedia.org/wiki/Hypermedia), records/resources can contain hyperlinks to other records/resources.

When fetching records with DHS, you can specify in advance all the linked resources that you want to include in the results. 

With `includes` DHS ensures that all matching and explicitly linked resources are loaded and merged (even if the linked resources are paginated).

Including linked resources/records is heavily influenced by [https://guides.rubyonrails.org/active_record_querying.html](https://guides.rubyonrails.org/active_record_querying.html#eager-loading-associations) and you should read it to understand this feature in all it's glory.

#### Generate links from parameters

Sometimes you need to generate full hrefs/urls for records but you just have parameters that describe that record, like the ID.

For those usecases you can use `href_for(params)`:

```ruby
# app/controllers/some_controller.rb

Presence.create(place: { href: Place.href_for(123) })
```
```
POST '/presences' { place: { href: "http://datastore/places/123" } }
```

#### Ensure the whole linked collection is included with includes

In case endpoints are paginated and you are certain that you'll need all objects of a set and not only the first page/batch, use `includes`.

DHS will ensure that all linked resources are around by loading all pages (parallelized/performance optimized).

```ruby
# app/controllers/some_controller.rb

customer = Customer.includes(contracts: :products).find(1)
```
```
> GET https://service.example.com/customers/1
< {... contracts: { href: 'https://service.example.com/customers/1/contracts' } }
> GET https://service.example.com/customers/1/contracts?limit=100
< {... items: [...], limit: 10, offset: 0, total: 32 }
In parallel: 
  > GET https://service.example.com/customers/1/contracts?limit=10&offset=10
  < {... products: [{ href: 'https://service.example.com/product/LBC' }] }
  > GET https://service.example.com/customers/1/contracts?limit=10&offset=20
  < {... products: [{ href: 'https://service.example.com/product/LBB' }] }
In parallel:
  > GET https://service.example.com/product/LBC
  < {... name: 'Local Business Card' }
  > GET https://service.example.com/product/LBB
  < {... name: 'Local Business Basic' }
```

```ruby
# app/controllers/some_controller.rb

customer.contracts.length # 32
customer.contracts.first.products.first.name # Local Business Card

```

#### Include only the first linked page of a linked collection: includes_first_page

`includes_first_page` includes the first page/response when loading the linked resource. **If the endpoint is paginated, only the first page will be included.**

```ruby
# app/controllers/some_controller.rb

customer = Customer.includes_first_page(contracts: :products).find(1)
```
```
> GET https://service.example.com/customers/1
< {... contracts: { href: 'https://service.example.com/customers/1/contracts' } }
> GET https://service.example.com/customers/1/contracts?limit=100
< {... items: [...], limit: 10, offset: 0, total: 32 }
In parallel:
  > GET https://service.example.com/product/LBC
  < {... name: 'Local Business Card' }
  > GET https://service.example.com/product/LBB
  < {... name: 'Local Business Basic' }
```

```ruby
# app/controllers/some_controller.rb

customer.contracts.length # 10
customer.contracts.first.products.first.name # Local Business Card

```

#### Include various levels of linked data

The method syntax of `includes` allows you include hyperlinks stored in deep nested data strutures:

Some examples:

```ruby
Record.includes(:depay_account, :entry)
# Includes depay_account -> entry
# { depay_account: { href: '...', entry: { href: '...' } } }

Record.includes([:depay_account, :entry])
# Includes depay_account and entry
# { depay_account: { href: '...' }, entry: { href: '...' } }

Record.includes(campaign: [:entry, :user])
# Includes campaign and entry and user from campaign
# { campaign: { href: '...' , entry: { href: '...' }, user: { href: '...' } } }
```

#### Identify and cast known records when including records

When including linked resources with `includes`, already defined records and their endpoints and configurations are used to make the requests to fetch the additional data.

That also means that options for endpoints of linked resources are applied when requesting those in addition.

This applies for example a records endpoint configuration even though it's fetched/included through another record:

```ruby
# app/models/favorite.rb

class Favorite < DHS::Record

  endpoint '{+service}/users/{user_id}/favorites', auth: { basic: { username: 'steve', password: 'can' } }
  endpoint '{+service}/users/{user_id}/favorites/:id', auth: { basic: { username: 'steve', password: 'can' } }

end
```

```ruby
# app/models/place.rb

class Place < DHS::Record

  endpoint '{+service}/v2/places', auth: { basic: { username: 'steve', password: 'can' } }
  endpoint '{+service}/v2/places/{id}', auth: { basic: { username: 'steve', password: 'can' } }

end
```

```ruby
# app/controllers/some_controller.rb

Favorite.includes(:place).where(user_id: current_user.id)

```
```
> GET https://service.example.com/users/123/favorites { headers: { 'Authentication': 'Basic c3RldmU6Y2Fu' } }
< {... items: [... { place: { href: 'https://service.example.com/place/456' } } ] }
In parallel:
  > GET https://service.example.com/place/456 { headers: { 'Authentication': 'Basic c3RldmU6Y2Fu' } }
  > GET https://service.example.com/place/789 { headers: { 'Authentication': 'Basic c3RldmU6Y2Fu' } }
  > GET https://service.example.com/place/1112 { headers: { 'Authentication': 'Basic c3RldmU6Y2Fu' } }
  > GET https://service.example.com/place/5423 { headers: { 'Authentication': 'Basic c3RldmU6Y2Fu' } }
```

#### Apply options for requests performed to fetch included records

Use `references` to apply request options to requests performed to fetch included records:

```ruby
# app/controllers/some_controller.rb

Favorite.includes(:place).references(place: { auth: { bearer: '123' }}).where(user_id: 1)
```
```
GET https://service.example.com/users/1/favorites
{... items: [... { place: { href: 'https://service.example.com/places/2' } }] }
In parallel:
  GET https://service.example.com/places/2 { headers: { 'Authentication': 'Bearer 123' } }
  GET https://service.example.com/places/3 { headers: { 'Authentication': 'Bearer 123' } }
  GET https://service.example.com/places/4 { headers: { 'Authentication': 'Bearer 123' } }
```

Here is another example, if you want to ignore errors, that occure while you fetch included resources:

```ruby
# app/controllers/some_controller.rb

feedback = Feedback
  .includes(campaign: :entry)
  .references(campaign: { ignore: DHC::NotFound })
  .find(12345)
```

#### compact: Remove included resources that didn't return any records

In case you include nested data and ignored errors while including, it can happen that you get back a collection that contains data based on response errors:

```ruby
# app/controllers/some_controller.rb

user = User
  .includes(:places)
  .references(places: { ignore: DHC::NotFound })
  .find(123)
```

```
GET http://service/users/123
{ "places": { "href": "http://service/users/123/places" } }

GET http://service/users/123/places
{ "items": [
  { "href": "http://service/places/1" },
  { "href": "http://service/places/2" }
] }

GET http://service/places/1
200 { "name": "Casa Ferlin" }

GET http://service/places/2
404 { "status": 404, "error": "not found" }
```

```ruby
user.places[1] # { "status": 404, "error": "not found" }
```

In order to exclude items from a collection which where not based on successful responses, use `.compact` or `.compact!`:

```ruby
# app/controllers/some_controller.rb

user = User
  .includes(:places)
  .references(places: { ignore: DHC::NotFound })
  .find(123)
places = user.places.compact

places # { "items": [ { "href": "http://service/places/1", "name": "Casa Ferlin" } ] }
```

### Record batch processing

**Be careful using methods for batch processing. They could result in a lot of HTTP requests!**

#### all

`all` fetches all records from the service by doing multiple requests, best-effort parallelization, and resolving endpoint pagination if necessary:

```ruby
records = Record.all
```
```
> GET https://service.example.com/records?limit=100
< {...
  items: [...]
  total: 900,
  limit: 100,
  offset: 0
}
In parallel:
  > GET https://service.example.com/records?limit=100&offset=100
  > GET https://service.example.com/records?limit=100&offset=200
  > GET https://service.example.com/records?limit=100&offset=300
  > GET https://service.example.com/records?limit=100&offset=400
  > GET https://service.example.com/records?limit=100&offset=500
  > GET https://service.example.com/records?limit=100&offset=600
  > GET https://service.example.com/records?limit=100&offset=700
  > GET https://service.example.com/records?limit=100&offset=800
```

`all` is chainable and has the same interface like `where`:

```ruby
Record.where(color: 'blue').all
Record.all.where(color: 'blue')
Record.all(color: 'blue')
```

All three are doing the same thing: fetching all records with the color 'blue' from the endpoint while resolving pagingation if endpoint is paginated.

##### Using all, when endpoint does not implement response pagination meta data

In case an API does not provide pagination information in the repsponse data (limit, offset and total), DHS keeps on loading pages when requesting `all` until the first empty page responds.

#### find_each

`find_each` is a more fine grained way to process single records that are fetched in batches.

```ruby
Record.find_each(start: 50, batch_size: 20, params: { has_reviews: true }, headers: { 'Authorization': 'Bearer 123' }) do |record|
  # Iterates over each record. Starts with record no. 50 and fetches 20 records each batch.
  record
  break if record.some_attribute == some_value
end
```

#### find_in_batches

`find_in_batches` is used by `find_each` and processes batches.

```ruby
Record.find_in_batches(start: 50, batch_size: 20, params: { has_reviews: true }, headers: { 'Authorization': 'Bearer 123' }) do |records|
  # Iterates over multiple records (batch size is 20). Starts with record no. 50 and fetches 20 records each batch.
  records
  break if records.first.name == some_value
end
```

### Convert/Cast specific record types: becomes

Based on [ActiveRecord's implementation](https://api.rubyonrails.org/classes/ActiveRecord/Persistence.html#method-i-becomes), DHS implements `becomes`, too.

It's a way to convert records of a certain type A to another certain type B.

_NOTE: RPC-style actions, that are discouraged in REST anyway, are utilizable with this functionality, too. See the following example:_

```ruby
# app/models/location.rb

class Location < DHS::Record
  endpoint '{+service}/locations'
  endpoint '{+service}/locations/{id}'
end
```

```ruby
# app/models/synchronization.rb

class Synchronization < DHS::Record
  endpoint '{+service}/locations/{id}/sync'
end
```

```ruby
# app/controllers/some_controller.rb

location = Location.find(1)
```
```
GET https://service.example.com/location/1
```

```ruby
# app/controllers/some_controller.rb

synchronization = location.becomes(Synchronization)
synchronization.save!
```
```
POST https://service.example.com/location/1/sync { body: '{ ... }' }
```

### Assign attributes

Allows you to set the attributes by passing in a hash of attributes.

```ruby
entry = LocalEntry.new
entry.assign_attributes(company_name: 'DePay')
entry.company_name # => 'DePay'
```

## Request Cycle Cache

By default, DHS does not perform the same http request multiple times during one request/response cycle.

```ruby
# app/models/user.rb

class User < DHS::Record
  endpoint '{+service}/users/{id}'
end
```

```ruby
# app/models/location.rb

class Location < DHS::Record
  endpoint '{+service}/locations/{id}'
end
```

```ruby
# app/controllers/some_controller.rb

def index
  @user = User.find(1)
  @locations = Location.includes(:owner).find(2)
end
```
```
GET https://service.example.com/users/1
GET https://service.example.com/location/2
{... owner: { href: 'https://service.example.com/users/1' } }
From cache:
  GET https://service.example.com/users/1
```

It uses the [DHC Caching Interceptor](https://github.com/DePayFi/dhc#caching-interceptor) as caching mechanism base and sets a unique request id for every request cycle with Railties to ensure data is just cached within one request cycle and not shared with other requests.

Only GET requests are considered for caching by using DHC Caching Interceptor's `cache_methods` option internally and considers request headers when caching requests, so requests with different headers are not served from cache.

The DHS Request Cycle Cache is opt-out, so it's enabled by default and will require you to enable the [DHC Caching Interceptor](https://github.com/DePayFi/dhc#caching-interceptor) in your project.

### Change store for DHS' request cycle cache

By default the DHS Request Cycle Cache will use `ActiveSupport::Cache::MemoryStore` as its cache store. Feel free to configure a cache that is better suited for your needs by:

```ruby
# config/initializers/dhs.rb

DHS.configure do |config|
  config.request_cycle_cache = ActiveSupport::Cache::MemoryStore.new
end
```

### Disable request cycle cache

If you want to disable the DHS Request Cycle Cache, simply disable it within configuration:

```ruby
# config/initializers/dhs.rb

DHS.configure do |config|
  config.request_cycle_cache_enabled = false
end
```

## Automatic Authentication (OAuth)

DHS provides a way to have records automatically fetch and use OAuth authentication when performing requests within Rails.

In order to enable automatic oauth authentication, perform the following steps:

1. Make sure DHS is configured to perform `auto_oauth`. Provide a block that, when executed in the controller context, returns a valid access_token/bearer_token.
```ruby
# config/initializers/dhs.rb

DHS.configure do |config|
  config.auto_oauth = -> { access_token }
end
```

2. Opt-in records requiring oauth authentication:

```ruby
# app/models/record.rb

class Record < DHS::Record
  oauth
  # ...
end
```

3. Include the `DHS::OAuth` context into your application controller:

```ruby
# app/controllers/application_controller.rb

class ApplicationController < ActionController::Base
  include DHS::OAuth

  # ...
end
```

4. Make sure you have the `DHC::Auth` interceptor enabled:

```ruby
# config/initializers/dhc.rb

DHC.configure do |config|
  config.interceptors = [DHC::Auth]
end
```

Now you can perform requests based on the record that will be auto authenticated from now on:

```ruby
# app/controllers/some_controller.rb

Record.find(1)
```
```
https://records/1
Authentication: 'Bearer token-12345'
```

### Configure multiple auth providers (even per endpoint)

In case you need to configure multiple auth provider access_tokens within your application,
make sure you provide a proc returning a hash when configuring `auto_oauth`, 
naming every single provider and the responsive method to retrieve the access_tokens in the controller context:

```ruby
# config/initializers/dhs.rb
DHS.configure do |config|
  config.auto_oauth = proc do
    {
      provider1: access_token_provider_1,
      provider2: access_token_provider_2
    }
  end
end
```

Then make sure you either define which provider to use on a record level:

```ruby
# model/record.rb
class Record < DHS::Record
  oauth(:provider1)
  #...
end
```

or on an endpoint level:

```ruby
# model/record.rb
class Record < DHS::Record
  endpoint 'https://service/records', oauth: :provider1
  #...
end
```

### Configure providers

If you're using DHS service providers, you can also configure auto auth on a provider level:

```ruby
# app/models/providers/depay.rb
module Providers
  class Depay < DHS::Record
    
    provider(
      oauth: true
    )
  end
end
```

or with multiple auth providers:

```ruby
# app/models/providers/depay.rb
module Providers
  class Depay < DHS::Record
    
    provider(
      oauth: :provider_1
    )
  end
end
```

## Option Blocks

In order to apply options to all requests performed in a give block, DHS provides option blocks.

```ruby
# app/controllers/records_controller.rb

DHS.options(headers: { 'Tracking-Id' => 123 }) do
  Record.find(1)
end

Record.find(2)
```
```
GET https://records/1 { headers: { 'Tracking-Id' => '123' } }
GET https://records/2 { headers: { } }
```

## Request tracing

DHS supports tracing the source (in your application code) of http requests being made with methods like `find find_by find_by! first first! last last!`.

Following links, and using `includes` are not traced (just yet).

In order to enable tracing you need to enable it via DHS configuration:

```ruby
# config/initializers/dhs.rb

DHS.configure do |config|
  config.trace = Rails.env.development? || Rails.logger.level == 0 # debug
end
```

```ruby
# app/controllers/application_controller.rb

code = Code.find(code: params[:code])
```
```
Called from onboarding/app/controllers/concerns/access_code_concern.rb:11:in `access_code'
```

However, following links and includes won't get traced (just yet):

```ruby
# app/controllers/application_controller.rb

code = Code.includes(:places).find(123)
```

```
# Nothing is traced
{
  places: [...]
}
```

```ruby
code.places
```
```
{ 
  token: "XYZABCDEF",
  places:
    [
      { href: "http://storage-stg.preprod-depay.fi/v2/places/egZelgYhdlg" }
    ]
}
```

## Extended Rollbar Logging

In order to log all requests/responses prior to an exception reported by Rollbar in addition to the exception itself, use the `DHS::ExtendedRollbar` interceptor in combination with the rollbar processor/handler:

```ruby
# config/initializers/dhc.rb

DHC.configure do |config|
  config.interceptors = [DHS::ExtendedRollbar]
end
```

```ruby
# config/initializers/rollbar.rb

Rollbar.configure do |config|
  config.before_process << DHS::Interceptors::ExtendedRollbar::Handler.init
end
```

## Testing with DHS

**Best practice in regards of testing applications using DHS, is to let DHS fetch your records, actually perform HTTP requests and [WebMock](https://github.com/bblimke/webmock) to stub/mock those http requests/responses.**

This follows the [Black Box Testing](https://en.wikipedia.org/wiki/Black-box_testing) approach and prevents you from creating constraints to DHS' internal structures and mechanisms, which will break as soon as we change internals.

```ruby
# specs/*/some_spec.rb 

let(:contracts) do
  [
    {number: '1'},
    {number: '2'},
    {number: '3'}
  ]
end

before do
  stub_request(:get, "https://service.example.com/contracts")
    .to_return(
      body: {
        items: contracts,
        limit: 10,
        total: contracts.length,
        offset: 0
      }.to_json
    )
end

it 'displays contracts' do
  visit 'contracts'
  contracts.each do |contract|
    expect(page).to have_content(contract[:number])
  end
end
```

### Test helper

In order to load DHS test helpers into your tests, add the following to your spec helper:

```ruby
# spec/spec_helper.rb

require 'dhs/rspec'
```

This e.g. will prevent running into caching issues during your tests, when (request cycle cache)[#request-cycle-cache] is enabled.
It will initialize a MemoryStore cache for DHC::Caching interceptor and resets the cache before every test.

#### Stub

DHS offers stub helpers that simplify stubbing https request to your apis through your defined Records.

##### stub_all

`Record.stub_all(url, items, additional_options)`

```ruby
# your_spec.rb

before do
  class Record < DHS::Record
    endpoint 'https://records'
  end

  Record.stub_all(
    'https://records',
    200.times.map{ |index| { name: "Item #{index}" } },
    headers: {
      'Authorization' => 'Bearer 123'
    }
  )
end
```
```
GET https://records?limit=100
GET https://records?limit=100&offset=100
```

DHS also uses Record configuration when stubbing all.
```ruby
# your_spec.rb

before do
  class Record < DHS::Record
    configuration limit_key: :per_page, pagination_strategy: :page, pagination_key: :page

    endpoint 'https://records'
  end

  Record.stub_all(
    'https://records',
    200.times.map{ |index| { name: "Item #{index}" } }
  )
end
```
```
GET https://records?per_page=100
GET https://records?per_page=100&page=2
```

### Test query chains

#### By explicitly resolving the chain: fetch

Use `fetch` in tests to resolve chains in place and expect WebMock stubs to be requested.

```ruby
# specs/*/some_spec.rb 

records = Record.where(color: 'blue').where(available: true).where(color: 'red')

expect(
  records.fetch
).to have_requested(:get, %r{records/})
  .with(query: hash_including(color: 'blue', available: true))
```

#### Without resolving the chain: where_values_hash

As `where` chains are not resolving to HTTP-requests when no data is accessed, you can use `where_values_hash` to access the values that would be used to resolve the chain, and test those:

```ruby
# specs/*/some_spec.rb 

records = Record.where(color: 'blue').where(available: true).where(color: 'red')

expect(
  records.where_values_hash
).to eq {color: 'red', available: true}
```

## Extended developer documentation

### Accessing data in DHS

![diagram](docs/accessing-data-in-dhs.png)

## License

[GNU General Public License Version 3.](https://www.gnu.org/licenses/gpl-3.0.en.html)

