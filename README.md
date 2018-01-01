# ActiveRecord::Prebatcher [![Build Status](https://travis-ci.org/joelvh/activerecord-prebatcher.svg?branch=master)](https://travis-ci.org/joelvh/activerecord-prebatcher)

Yet Another N+1 COUNT Query Killer for ActiveRecord, counter\_cache alternative.  
ActiveRecord::Prebatcher allows you to cache count of associated records by eager loading.

This is another version of [activerecord-precounter](https://github.com/k0kubun/activerecord-precounter),
which can do more than just `count`. You can use other calculations like `sum`, `average`, `minimum`, `maximum` and custom batching.

## Synopsis

### N+1 count query

Sometimes you may see many count queries for one association.
You can use counter\_cache to solve it, but you need to ALTER table and concern about dead lock to use counter\_cache.

```rb
tweets = Tweet.all
tweets.each do |tweet|
  p tweet.favorites.count
end
# SELECT `tweets`.* FROM `tweets`
# SELECT COUNT(*) FROM `favorites` WHERE `favorites`.`tweet_id` = 1
# SELECT COUNT(*) FROM `favorites` WHERE `favorites`.`tweet_id` = 2
# SELECT COUNT(*) FROM `favorites` WHERE `favorites`.`tweet_id` = 3
# SELECT COUNT(*) FROM `favorites` WHERE `favorites`.`tweet_id` = 4
# SELECT COUNT(*) FROM `favorites` WHERE `favorites`.`tweet_id` = 5
```

### Count eager loading

#### precount

With activerecord-prebatcher gem installed, you can use `ActiveRecord::Prebatcher#precount` method
to eagerly load counts of associated records (which is backwards-compatible with activerecord-precounter gem).
Like `preload`, it loads counts by multiple queries

```rb
tweets = Tweet.all
ActiveRecord::Prebatcher.new(tweets).precount(:favorites)
tweets.each do |tweet|
  p tweet.favorites_count
end
# SELECT `tweets`.* FROM `tweets`
# SELECT COUNT(`favorites`.`tweet_id`), `favorites`.`tweet_id` FROM `favorites` WHERE `favorites`.`tweet_id` IN (1, 2, 3, 4, 5) GROUP BY `favorites`.`tweet_id`
```

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'activerecord-prebatcher'
```

## Limitation

Target `has_many` association must have inversed `belongs_to`.
i.e. `ActiveRecord::Prebatcher.new(tweets).precount(:favorites)` needs both `Tweet.has_many(:favorites)` and `Favorite.belongs_to(:tweet)`.

Unlike [activerecord-precount](https://github.com/k0kubun/activerecord-precount), the cache store is not ActiveRecord association and it does not utilize ActiveRecord preloader.
Thus you can't use `preload` to eager load counts for nested associations. And currently there's no JOIN support.

## License

MIT License
