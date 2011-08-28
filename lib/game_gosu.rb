require 'gosu'
require 'chingu'
require 'texplay'

EXTRACT_PATH = File.expand_path('../..', __FILE__)

include Gosu
include Chingu

def image_path(res)
  File.expand_path res, File.join(EXTRACT_PATH, 'media/images')
end

class Map 
  BACKGROUND_COLOR = Color.rgba(30, 10, 10, 255)
  
  attr_reader :grid_width, :grid_height
    
  def to_rect; Rect.new(0, 0, @grid_width * Tile::WIDTH, @grid_height * Tile::HEIGHT); end

  def initialize(grid_width, grid_height)
    @grid_width, @grid_height = grid_width, grid_height
    @tiles = Array.new(@grid_height) { Array.new(@grid_width) }
    
    possible_tiles = [
        *([Tile::Grass] * 50),
        *([Tile::Foxhole] * 5)
    ]
    
    @grid_height.times do |y|
      @grid_width.times do |x|
         @tiles[y][x] = possible_tiles.sample.new [x, y]
         @tiles[y][x] = Tile::Foxhole.new [x, y] if y % 9 == 2         
         @tiles[y][x] = Tile::Earthwork.new [x, y] if y % 7 == 5
      end
    end
    
    t = Time.now
    @buffers = Hash.new {|h, k| h[k] = [] }
    @tiles.each {|r| r.reverse_each {|t| @buffers[t.y] << t } }
    @records = @buffers.values.map {|b| $window.record { b.each {|t| t.draw }}}
    puts "Recorded rows in #{Time.now - t}s"
  end
  
  # Draws all tiles (only) visible in the window.
  def draw(offset_x, offset_y)
    $window.draw_quad -1000, -1000, BACKGROUND_COLOR,
              2000, -1000, BACKGROUND_COLOR,
              2000, 2000, BACKGROUND_COLOR,
              -1000, 2000, BACKGROUND_COLOR, -Float::INFINITY
              
    #@tiles.each {|row| row.reverse_each {|tile| tile.draw } }
    @records.each {|r| r.draw_rot offset_x, offset_y, 0, 0, 0, 0, 1, 1 }    
  end
end

class Tile < GameObject
  class Grass < Tile
    def sheet_pos; 10; end
  end
  
  class Dirt < Tile
    def sheet_pos; 0; end
  end
  
  class Foxhole < Tile
    def sheet_pos; 50; end
    
    def draw_on(window)
      super(window)
      draw_objects_on(window)
    end
  end
  
  class Earthwork < Dirt
    def sheet_pos; 0; end
    
    def initialize(grid_position) 
      super(grid_position)
      add_block_on_top EarthworkTop
    end    
  end
  
  class EarthworkTop < Tile
    def sheet_pos; 30; end
  end
  
  WIDTH, HEIGHT = 32, 16
    
  attr_reader :z
  
  def initialize(grid_position, options = {}) 
    unless defined? @@sprites
      @@sprites = Image.load_tiles($window, image_path("tiles.png"), 34, 34, false)
    end
    
    @grid_position = grid_position
    
    options[:image] = @@sprites[sheet_pos]
    options[:x] = (@grid_position[1] + @grid_position[0]) * WIDTH / 2
    options[:y] = (@grid_position[1] - @grid_position[0]) * HEIGHT / 2
    options[:rotation_center] = :center_center        
    options[:zorder] = options[:y]
    
    @on_top_of = options[:on_top_of]
    @z = @on_top_of ? @on_top_of.z + HEIGHT : HEIGHT
    options[:y] -= @z
    
    @objects = []
    @block_on_top = @block_underneath = nil
    
    super(options)
  end
  
  def add_block_on_top(type)
    @block_on_top = type.new(@grid_position, on_top_of: self)
  end
  
  def draw
    super
    @objects.each { |o| o.draw }
    @block_on_top.draw if @block_on_top
  end
end

class World < GameState
  attr_reader :map, :camera_offset_x, :camera_offset_y
  
  def setup
    @map = Map.new 200, 100           
    @camera_offset_x, @camera_offset_y = [-240, 200] 
  end
  
  def draw   
    $window.translate @camera_offset_x, @camera_offset_y do
      @map.draw @camera_offset_x, @camera_offset_y   
    end
  end
end

class GameWindow < Chingu::Window
  def setup
    push_game_state World
  end
end

GameWindow.new.show
