require 'ray'
require 'forwardable'

EXTRACT_PATH = File.expand_path('../..', __FILE__)

include Ray

require_relative 'ray_ext'

def image_path(res)
  File.expand_path File.join(File.dirname(__FILE__), '../media/images', res)
end

class Map
  include Helper
  
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
    @buffers = Hash.new {|h, k| h[k] = Ray::BufferRenderer.new :static, Ray::Vertex }
    @tiles.each do |row|
      row.reverse_each do |t|
        base_sprite = t.instance_variable_get(:@sprite)
        @buffers[base_sprite.y] << base_sprite
        upper_block = t.block_on_top
        @buffers[base_sprite.y] << upper_block.instance_variable_get(:@sprite) if upper_block
      end
    end
    puts "Buffered rows in #{Time.now - t}s"
    t = Time.now
    @buffers.each_value(&:update)
    puts "Updated buffer rows in #{Time.now - t}s"
  end
  
  # Draws all tiles (only) visible in the window.
  def draw_on(window)
    window.clear Color.new(30, 10, 10, 255)
    #@tiles.each {|r| r.reverse_each {|t| t.draw_on window } }
    @buffers.each_value {|buffer| window.draw buffer }
  end
end

class Tile
  class Grass < Tile
    def sheet_pos; [0, 1]; end
  end
  
  class Dirt < Tile
    def sheet_pos; [0, 0]; end
  end
  
  class Foxhole < Tile
    def sheet_pos; [0, 5]; end
  end
  
  class Earthwork < Dirt
    def sheet_pos; [0, 0]; end
    
    def initialize(grid_position) 
      super(grid_position)
      add_block_on_top EarthworkTop
    end    
  end
  
  class EarthworkTop < Tile
    def sheet_pos; [0, 3]; end
  end
  
  WIDTH, HEIGHT = 32, 16
  
  include Helper
  
  attr_reader :objects, :block_on_top, :block_underneath
  
  def initialize(grid_position, options = {}) 
    unless defined? @@sprite
      @@sprite = sprite image(image_path("tiles.png"))
      @@sprite.sheet_size = [10, 10]
    end
    
    @sprite = @@sprite.dup
    @sprite.sheet_pos = sheet_pos
    @grid_position = grid_position.to_vector2
    @sprite.x = (@grid_position.y + @grid_position.x) * WIDTH / 2
    @sprite.y = (@grid_position.y - @grid_position.x) * HEIGHT / 2
    
    @on_top_of = options[:on_top_of]
    @sprite.y -= WIDTH / 2 if @on_top_of
    @objects = []
    @block_on_top = @block_underneath = nil
  end
  
  def add_block_on_top(type)
    @block_on_top = type.new(@grid_position, on_top_of: self)
  end
  
  def draw_on(window)
    window.draw @sprite
    @block_on_top.draw_on(window) if @block_on_top
  end
end

class World < Scene
  attr_reader :map
  
  def setup   
    @map = Map.new 200, 100
    @camera = window.default_view        
    @camera.center = [window.size.width / 2 + 240, window.size.width / 2 - 200] 
  end
  
  def register   
    render do |win| 
      win.with_view @camera do
        @map.draw_on(win)          
      end
    end
  end  
end


Ray.game "2.5D", size: [800, 600] do
  register do
    on :quit, &method(:exit!)
    on :key_press, key(:escape), &method(:exit!)
  end
  
  scene_classes = [World]
  scene_classes.each {|s| s.bind(self) }
  scenes << :world
end
