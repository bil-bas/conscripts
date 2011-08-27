require 'gosu'
require 'chingu'
require 'texplay'

EXTRACT_PATH = File.expand_path('../..', __FILE__)

include Gosu
include Chingu

def image_path(res)
  File.expand_path File.join(File.dirname(__FILE__), '../media/images', res)
end

class WorldObject < GameObject 
  attr_accessor :z
  
  def initialize(options = {})    
    options = {
	   rotation_center: :bottom_center,
	   z: 0,
    }.merge! options	
	
    create_shadow(options[:position]) 
	
	@z = options[:z]
	
	super(options)	
  end

  def create_shadow(position)
    unless defined? @@shadow
      @@shadow = TexPlay.create_image $window, 32, 32
      #center = img.size / 2
      32.times do |x|
	    32.times do |y|
          @@shadow.pixel(x, y, color: [0, 0, 0, 0.5 - distance(x, y, 15.5, 15.5) * 0.05])
		end
      end
    end
  end
 
  def draw
    @@shadow.draw_rot x, y, y - z, 0, 0.5, 0.5, 1, 0.5
	@image.draw_rot x, y, y - z, 0, 0.5, 1
  end
end

class DynamicObject < WorldObject
  def initialize(grid_position, options = {}) 
    @velocity_z = 0
    
    super(grid_position, options) 
  end
  
  def update
      if @velocity_z != 0 or z > 0
      @velocity_z -= 0.4
      self.z += @velocity_z
      
      if z <= 0
        self.z = 0
        @velocity_z = 0
      end
    end
  end
end

class StaticObject < WorldObject
    attr_reader :tile
	
	def initialize(grid_position, options = {})       
	  super(options)
	  @tile = parent.map.tile_at_grid(*grid_position)	  
	  @tile.add_object(self)
    end
end


class Tree < StaticObject
  def initialize(grid_position, options = {})
	unless defined? @@sprites
	  @@sprites = Image.load_tiles($window, image_path("characters.png"), 34, 34, false)
	end
	
	options[:image] = @@sprites[rand(3)]
     
    super(grid_position, options)
  end  
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
  
  def tile_at_position(x, y)
    #tile_at_grid(((x - y * 12.0) / 24.0).to_i, (y / 6.0).to_i)
  end
  
  def tile_at_grid(x, y)
    if x.between?(0, @grid_width - 1) and y.between?(0, @grid_height - 1)
      @tiles[y][x]
    else
      nil
    end
  end
  
  # Yields every tile visible to the view.
  def each_visible(view, &block)
=begin
    rect = view.rect
		
    min_y = [((rect.y - 16) / 8).floor, 0].max
    max_y = [((rect.y + rect.height) / 4.0).ceil, @tiles.size - 1].min
	
	visible_rows = @tiles[min_y..max_y]
	if visible_rows
	  visible_rows.each do |row|
	    #min_x = [((rect.x - 16) / tile_size).floor, 0].max
		#max_x = [((rect.x + rect.width) / 24).ceil, @tiles.first.size - 1].min
		tiles = row#[min_x..max_x]
		tiles.reverse_each {|tile| yield tile } if tiles
	  end
	end
=end
   @tiles.each {|r| r.reverse_each {|t| yield t } }
  end
  
  # List of all objects visible in the view.
  def visible_objects(view)
    objects = []
    each_visible(view) {|tile| objects.push *tile.objects }
    objects
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
    @dynamic_objects = [] # Objects that need #update
    
    @map = Map.new 50, 50
    
    # Make some animated objects.
    #100.times do |i|
    #  Enemy.new(self, [i * 16, rand * window.size.height])
    #end
	    
    # Make some static objects.
    50.times do
      Tree.new([rand(@map.grid_width), rand(@map.grid_height)])
    end
          
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
    
  def update
	  start_at = Time.now
		if holding? :left
		  @camera_offset_x += 10.0 / zoom
		elsif holding? :right
		  @camera_offset_x -= 10.0 / zoom
		end	
		if holding? :up
		  @camera_offset_y += 10.0 / zoom
		elsif holding? :down
		  @camera_offset_y -= 10.0 / zoom
		end	        
      
=begin
      # Checking for collision on the screen is significantly slower than just rendering everything.
      clip_rect = @camera.rect
      @visible_objects = @dynamic_objects.select {|o| o.to_rect.collide? clip_rect }

      # Update visible dynamic objects and stop them moving off the map. Others will just sleep off the side of the map.
      @visible_objects.each(&:update)
      rect = @map.to_rect
      max_x, max_y = rect.width, rect.height
      @visible_objects.each do |obj|
        half_w = obj.width / 2
        obj.x = [[obj.x, half_w].max, max_x - half_w].min
        obj.y = [[obj.y, half_w].max, max_y - half_w].min
      end

      @visible_objects += @map.visible_objects(@camera)
      @visible_objects.sort_by!(&:z_order)
=end
          
	  @fps_text = "Zoom: #{zoom} FPS: #{fps.round}"
	  rescue => ex
	  puts ex
	  puts ex.backtrace
	  exit
	  
  end
  
  def draw      	  
      $window.translate @camera_offset_x, @camera_offset_y do
        @map.draw	

        #@visible_objects.each {|obj| obj.draw_shadow_on win }      
        #@visible_objects.each {|obj| obj.draw_on win }
      end
	  
	  @font.draw @fps_text, 0, 0, Float::INFINITY
  rescue => ex
	  puts ex
	  puts ex.backtrace
	  exit
  end
end

class GameWindow < Chingu::Window
  def setup
    push_game_state World
  end
end

GameWindow.new.show
