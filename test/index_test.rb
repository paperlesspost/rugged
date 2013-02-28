require "test_helper"
require 'base64'
require 'tempfile'
require 'fileutils'

class IndexTest < Rugged::TestCase
  def self.new_index_entry
      now = Time.now
      {
        :path => "new_path",
        :oid => "d385f264afb75a56a5bec74243be9b367ba4ca08",
        :mtime => now,
        :ctime => now,
        :file_size => 1000,
        :dev => 234881027,
        :ino => 88888,
        :mode => 33199,
        :uid => 502,
        :gid => 502,
        :stage => 3,
      }
  end

  def setup
    path = File.dirname(__FILE__) + '/fixtures/testrepo.git/index'
    @index = Rugged::Index.new(path)
  end

  def test_iteration
    enum = @index.each
    assert enum.kind_of? Enumerable

    i = 0
    @index.each { |e| i += 1 }
    assert_equal @index.count, i
  end

  def test_index_size
    assert_equal 2, @index.count
  end

  def test_empty_index
    @index.clear
    assert_equal 0, @index.count
  end

  def test_remove_entries
    @index.remove 'new.txt'
    assert_equal 1, @index.count
  end

  def test_get_entry_data
    e = @index[0]
    assert_equal 'README', e[:path]
    assert_equal '1385f264afb75a56a5bec74243be9b367ba4ca08', e[:oid]
    assert_equal 1273360380, e[:mtime].to_i
    assert_equal 1273360380, e[:ctime].to_i
    assert_equal 4, e[:file_size]
    assert_equal 234881026, e[:dev]
    assert_equal 6674088, e[:ino]
    assert_equal 33188, e[:mode]
    assert_equal 501, e[:uid]
    assert_equal 0, e[:gid]
    assert_equal false, e[:valid]
    assert_equal 0, e[:stage]

    e = @index[1]
    assert_equal 'new.txt', e[:path]
    assert_equal 'fa49b077972391ad58037050f2a75f74e3671e92', e[:oid]
  end

  def test_iterate_entries
    itr_test = @index.sort { |a, b| a[:oid] <=> b[:oid] }.map { |e| e[:path] }.join(':')
    assert_equal "README:new.txt", itr_test
  end

  def test_update_entries
    now = Time.at Time.now.to_i
    e = @index[0]

    e[:oid] = "12ea3153a78002a988bb92f4123e7e831fd1138a"
    e[:mtime] = now
    e[:ctime] = now
    e[:file_size] = 1000
    e[:dev] = 234881027
    e[:ino] = 88888
    e[:mode] = 33199
    e[:uid] = 502
    e[:gid] = 502
    e[:stage] = 3

    @index.add(e)
    new_e = @index.get e[:path], 3

    assert_equal e, new_e
  end

  def test_add_new_entries
    e = IndexTest.new_index_entry
    @index << e
    assert_equal 3, @index.count
    itr_test = @index.sort { |a, b| a[:oid] <=> b[:oid] }.map { |x| x[:path] }.join(':')
    assert_equal "README:new_path:new.txt", itr_test
  end
end

class IndexWriteTest < Rugged::TestCase
  def setup
    path = File.dirname(__FILE__) + '/fixtures/testrepo.git/index'
    @tmppath = Tempfile.new('index').path
    FileUtils.copy(path, @tmppath)
    @index = Rugged::Index.new(@tmppath)
  end

  def teardown
    File.delete(@tmppath)
  end

  def test_raises_when_writing_invalid_entries
    assert_raises TypeError do
      @index.add(21)
    end
  end

  def test_can_write_index
    e = IndexTest.new_index_entry
    @index << e

    e[:path] = "else.txt"
    @index << e

    @index.write

    index2 = Rugged::Index.new(@tmppath)

    itr_test = index2.sort { |a, b| a[:oid] <=> b[:oid] }.map { |x| x[:path] }.join(':')
    assert_equal "README:else.txt:new_path:new.txt", itr_test
    assert_equal 4, index2.count
  end
end

class IndexWorkdirTest < Rugged::TestCase
  def setup
    @tmppath = Dir.mktmpdir
    @repo = Rugged::Repository.init_at(@tmppath, false)
    @index = @repo.index
  end

  def teardown
    FileUtils.remove_entry_secure(@tmppath)
  end

  def test_adding_a_path
    File.open(File.join(@tmppath, 'test.txt'), 'w') do |f|
      f.puts "test content"
    end
    @index.add('test.txt')
    @index.write

    index2 = Rugged::Index.new(@tmppath + '/.git/index')
    assert_equal index2[0][:path], 'test.txt'
  end

  def test_reloading_index
    File.open(File.join(@tmppath, 'test.txt'), 'w') do |f|
      f.puts "test content"
    end
    @index.add('test.txt')
    @index.write

    rindex = Rugged::Index.new(File.join(@tmppath, '/.git/index'))
    e = rindex['test.txt']
    assert_equal 0, e[:stage]

    rindex << IndexTest.new_index_entry
    rindex.write

    assert_equal 1, @index.count
    @index.reload
    assert_equal 2, @index.count

    e = @index.get 'new_path', 3
    assert_equal e[:mode], 33199
  end
end

class IndexRepositoryTest < Rugged::TestCase
  include Rugged::TempRepositoryAccess

  def test_idempotent_read_write
    head_sha = Rugged::Reference.lookup(@repo,'HEAD').resolve.target
    tree = @repo.lookup(head_sha).tree
    index = @repo.index
    index.read_tree(tree)

    index_tree_sha = index.write_tree
    index_tree = @repo.lookup(index_tree_sha)
    assert_equal tree.oid, index_tree.oid
  end

  def test_build_tree_from_index
    head_sha = Rugged::Reference.lookup(@repo,'refs/remotes/origin/packed').resolve.target
    tree = @repo.lookup(head_sha).tree

    index = @repo.index
    index.read_tree(tree)
    index.remove('second.txt')

    new_tree_sha = index.write_tree
    assert head_sha != new_tree_sha
    assert_nil @repo.lookup(new_tree_sha)['second.txt']
  end
end
