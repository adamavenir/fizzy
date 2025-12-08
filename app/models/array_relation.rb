# Wraps an array to provide ActiveRecord::Relation-like interface
# for geared_pagination compatibility
class ArrayRelation
  attr_reader :records

  def initialize(records)
    @records = records
  end

  # Geared pagination calls these methods
  def unscope(*args)
    self
  end

  def count
    @records.length
  end

  def size
    @records.size
  end

  def length
    @records.length
  end

  def limit(count)
    self.class.new(@records.take(count))
  end

  def offset(count)
    self.class.new(@records.drop(count))
  end

  def load
    self
  end

  def loaded?
    true
  end

  def any?
    @records.any?
  end

  def none?
    @records.none?
  end

  def empty?
    @records.empty?
  end

  # Make it enumerable
  include Enumerable

  def each(&block)
    @records.each(&block)
  end

  def to_a
    @records
  end

  # For debugging
  def inspect
    "#<ArrayRelation count=#{count}>"
  end
end
