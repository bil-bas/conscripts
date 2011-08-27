require 'gosu'
require 'chingu'
require 'texplay'

EXTRACT_PATH = File.expand_path('../..', __FILE__)

include Gosu
include Chingu

def image_path(res)
  File.expand_path File.join(File.dirname(__FILE__), '../media/images', res)
end

class Map
  attr_reader :grid_width, :grid_height
    
  def to_rect; Rect.new(0, 0, @grid_width * Tile::WIDTH, @grid_height * Tile::HEIGHT); end

  def initialize(grid_width, grid_height)
    @grid_width, @grid_height = grid_width, grid_height
    @tiles = Array.new(@grid_height) { Array.new(@grid_width) }
    
    possible_tiles = [
        *([Tile::Grass] * 50),
        *([Tile::Earthwork] * 0),
        *([Tile::Dirt] * 0),
        *([Tile::Sand] * 0),
        *([Tile::Foxhole] * 5)
    ]
    @grid_height.times do |y|
      @grid_width.times do |x|
         @tiles[y][x] = possible_tiles.sample.new [x, y]
         @tiles[y][x] = Tile::Foxhole.new [x, y] if y % 9 == 2
         
         @tiles[y][x] = Tile::Earthwork.new [x, y] if y % 7 == 5
      end
    end
  end
  
  BACKGROUND_COLOR = Color.rgba(30, 10, 10, 255)
  
  # Draws all tiles (only) visible in the window.
  def draw
    $window.draw_quad 0, 0, BACKGROUND_COLOR,
              $window.width, 0, BACKGROUND_COLOR,
              $window.width, $window.height, BACKGROUND_COLOR,
              0, $window.height, BACKGROUND_COLOR, 0
              
    @tiles.each {|row| row.reverse_each {|tile| tile.draw } }
  end
end

class Tile < GameObject
  class Grass < Tile
    def sheet_pos; 10; end
  end
  
  class Dirt < Tile
    def sheet_pos; 0; end
  end
  
  class Sand < Tile
    def sheet_pos; 20; end
  end
  
  class Foxhole < Tile
    def sheet_pos; 50; end
    
    def add_object(object)      
      super(object)
      object.z -= HEIGHT
    end
    
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
    
    def object_position
      [x, y, 4]
    end
  end
  
  WIDTH, HEIGHT = 32, 16
    
  attr_reader :objects, :z
  
  def object_position
    [x, y, z]
  end
  
  def initialize(grid_position, options = {}) 
    unless defined? @@sprites
      @@sprites = Image.load_tiles($window, image_path("tiles.png"), 34, 34, false)
    end
    
    options[:image] = @@sprites[sheet_pos]
    @grid_position = grid_position
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
  
  def add_object(object)
    if @block_on_top
      @block_on_top.add_object(object)
    else
      @objects << object
      object.x, object.y = object_position
    end
  end
  
  def draw
    super
    @objects.each { |o| o.draw }
    @block_on_top.draw if @block_on_top
  end
end

class World < GameState
  attr_reader :map
  
  def setup
    @map = Map.new 100, 50   
          
    @fps_text = Text.new("0", size: 14)
    
    @camera_offset_x, @camera_offset_y = [0, @map.to_rect.center_y] 
    @zoom = 1
    
    @font = Font.new $window, default_font_name, 24
  end
  
  def add_object(object)
    case object
      when DynamicObject
        @dynamic_objects << object
    end
  end
  
  def zoom
    @zoom
  end
  
  def draw            
    $window.translate @camera_offset_x, @camera_offset_y do
      @map.draw    
    end
  end
end

class GameWindow < Chingu::Window
  def setup
    push_game_state World
  end
end

GameWindow.new.show
