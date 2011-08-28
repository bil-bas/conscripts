require 'ray'
require 'pry'
require 'forwardable'
require 'benchmark'

EXTRACT_PATH = File.expand_path('../..', __FILE__)

include Ray

require_relative 'ray_ext'

def image_path(res)
  File.expand_path File.join(File.dirname(__FILE__), '../media/images', res)
end

class GameObject
  extend Forwardable
  include Helper
  
  def_delegators :@scene, :window
  def_delegators :@sprite, :x
  
  attr_reader :scene, :z  
  
  def width; @sprite.sprite_width; end
  def pos; Vector2[x, y]; end
  alias_method :position, :pos 
  def pos=(pos)
    self.x, self.y = *pos
  end
  alias_method :position=, :pos=
  
  def x=(value)
    @sprite.x = @shadow.x = value
  end
  
  def y; @sprite.y + @z; end
  alias_method :z_order, :y
  
  def y=(value)
    @sprite.y = value - @z
    @shadow.y = y
    value
  end
  
  def z=(value)
    @sprite.y += @z - value
    @z = value
  end
  
  def initialize(scene, sprite, position) 
    @sprite = sprite
	@sprite.pos = position
  
    @z = 0 
    
    create_shadow(position)
    
    scene.add_object(self)

    register(scene)   
  end

  def create_shadow(position)
    unless defined? @@shadow
      img = Image.new [32, 32]
      center = img.size / 2
      img.map_with_pos! do |color, x, y|
        brightness = Vector2[x, y].distance(center) * 10 + 90
        Color.new(brightness, brightness, brightness) 
      end
      @@shadow = sprite img
	  @@shadow.scale = [0.5, 0.25]
      @@shadow.origin = center
      @@shadow.blend_mode = :multiply
    end
    
    @shadow = @@shadow.dup
    @shadow.position = position
  end
  
  def register(scene)
    self.event_runner = scene.event_runner
    @scene            = scene
  end
  
  def to_rect
    width = @sprite.sprite_width
    Rect.new(x - width / 2, y - width / 2, width, width)
  end
  
  def draw_on(win)
    win.draw @sprite
  end
  
  def draw_shadow_on(win)
    win.draw @shadow
  end
end

class DynamicObject < GameObject
  def initialize(scene, sprite, position) 
    @velocity_z = 0
    @animations = []
    
    super(scene, sprite, position)
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
    
    @animations.each(&:update)
  end
  
  def animated?
    @animations.any?(&:running?)
  end
end

class StaticObject < GameObject
    attr_reader :tile
	def initialize(scene, sprite, grid_position) 
      @tile = scene.map.tile_at_grid(*grid_position)	  
	  super(scene, sprite, @tile.object_position)
	  @tile.add_object(self)
    end
end

class Bloke < DynamicObject
  ANIMATION_DURATION = 0.3
  
  def initialize(scene, position)
    sprite = sprite image_path("characters.png"), at: position    
    sprite.sheet_size = [3, 3]
    sprite.origin = [sprite.sprite_width / 2, sprite.sprite_height - 1]
	
    super(scene, sprite, position)
  end
  
  def walk_animation(translation, sheet_row)
    @animations.clear
    @animations << sprite_animation(from: [0, sheet_row], to: [@sprite.sheet_size.width, sheet_row],
                                       duration: ANIMATION_DURATION).start(@sprite)
    @animations << translation(of: translation.to_vector2 * speed, duration: ANIMATION_DURATION).start(self)
  end
end

class Enemy < Bloke
  def speed; 16; end
  
  def register(scene)
    super(scene)
  end
  
  def update
    
    super
  end
end

class Tree < StaticObject
  def initialize(scene, grid_position)
	unless defined? @@sprite
	  @@sprite = sprite image(image_path("characters.png"))
	  @@sprite.sheet_size = [3, 3]
	  @@sprite.origin = [17, 32]
	end
	
    sprite = @@sprite.dup
	sprite.sheet_pos = [rand(3), 0]
     
    super(scene, sprite, grid_position)
  end  
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
  
  def buffer_drawing
    t = Time.now
    @buffers = Hash.new {|h, k| h[k] = Ray::BufferRenderer.new :static, Ray::Vertex }
    @tiles.each do |row|
      row.reverse_each do |t|
        t.sprites.each {|sprite| @buffers[t.y] << sprite }
      end
    end
    puts "Buffered #{@buffers.size} rows in #{Time.now - t}s"
    t = Time.now
    @buffers.each_value(&:update)
    puts "Updated buffer rows in #{Time.now - t}s"
  end
  
  def tile_at_position(x, y)
    tile_at_grid(((x - y * 12.0) / 24.0).to_i, (y / 6.0).to_i)
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
  
  # Draws all tiles (only) visible in the window.
  def draw_on(window, min_y, max_y)
    window.clear Color.new(30, 10, 10, 255)
    
    min_y -= Tile::HEIGHT
    max_y += Tile::HEIGHT * 2
    
    @buffers.to_a.each do |y, buffer|
      window.draw buffer if y > min_y and y < max_y
    end
  end
end

class Tile
  class Grass < Tile
    def sheet_pos; [0, 1]; end
  end
  
  class Dirt < Tile
    def sheet_pos; [0, 0]; end
  end
  
  class Sand < Tile
    def sheet_pos; [0, 2]; end
  end
  
  class Foxhole < Tile
    def sheet_pos; [0, 4]; end
	
	def add_object(object)	  
	  super(object)
	  object.y += WIDTH / 2
	end
	
	def draw_on(window)
	  super(window)
	  draw_objects_on(window)
	end
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
	
    def object_position
	  @sprite.pos + [0, 6]
    end
  end
  
  WIDTH, HEIGHT = 32, 16
  
  include Helper
  
  attr_reader :objects, :block_on_top, :block_underneath
  
  @@sprites = {}
  
  def y; @sprite.y - @z; end
  
  def object_position
    @sprite.pos
  end
  
  def sprites
    sprites = [@sprite]
    objects.each {|o| sprites << o.instance_variable_get(:@shadow) }
    objects.each {|o| sprites << o.instance_variable_get(:@sprite) }
    sprites += @block_on_top.sprites if @block_on_top
    sprites
  end
  
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
	@sprite.origin = [WIDTH / 2, HEIGHT / 2]
	
	@on_top_of = options[:on_top_of]
    @z = @on_top_of ? HEIGHT : 0
	@sprite.y -= @z
    @objects = []
	@block_on_top = @block_underneath = nil
  end
  
  def add_block_on_top(type)
	@block_on_top = type.new(@grid_position, on_top_of: self)
  end
  
  def add_object(object)
    if @block_on_top
	  @block_on_top.add_object(object)
	else
      @objects << object
	  object.position = object_position
	end
  end
  
  def draw_on(window)
    window.draw @sprite
	draw_shadows_on(window)
	draw_objects_on(window)
	@block_on_top.draw_on(window) if @block_on_top
  end
	
  def draw_objects_on(window) 
	@objects.each { |o| o.draw_on window }
  end
  
  def draw_shadows_on(window)
    @objects.each { |o| o.draw_shadow_on window }
  end
end

class World < Scene
  attr_reader :map
  
  def setup
    @dynamic_objects = [] # Objects that need #update
    
    @map = Map.new 50, 50
    
    # Make some animated objects.
    #100.times do |i|
    #  Enemy.new(self, [i * 16, rand * window.size.height])
    #end
	    
    # Make some static objects.
    200.times do
      Tree.new(self, [rand(@map.grid_width), rand(@map.grid_height)])
    end
    
    @map.buffer_drawing
   
    @camera = window.default_view    
      
    @half_size = window.size / 2
      
	@fps_text = Text.new("0", size: 14)
	
	@camera.center = [@map.to_rect.center.x, 0] 
	
    init_fps
  end
  
  def add_object(object)
    case object
      when DynamicObject
        @dynamic_objects << object
    end
  end
  
  def zoom
	window.size.height.to_f / @camera.size.height
  end
  
  def register   
  	on :wheel_motion do |pos, delta|
	  center = @camera.center
	  
	  if delta > 0
		  delta.times do
			@camera.zoom_by 2 unless zoom == 8
		  end
	  elsif delta < 0
		  (-delta).times do
			@camera.unzoom_by 2 unless zoom == 0.25
		  end
	  end
	  
	  @camera.center = center
	end
	
    always do
	  start_at = Time.now
		if holding? :left
		  @camera.x -= 10.0 / zoom
		elsif holding? :right
		  @camera.x += 10.0 / zoom
		end	
		if holding? :up
		  @camera.y -= 10.0 / zoom
		elsif holding? :down
		  @camera.y += 10.0 / zoom
		end
	        
      # Move the camera to the player position, but don't let the user see over the edge of the map.
      #camera_x = [[@player.x, @half_size.w].max, @map.to_rect.width - @half_size.w].min
      #camera_y = [[@player.y, @half_size.h].max, @map.to_rect.height - @half_size.h].min
      #@camera.center = [camera_x, camera_y] 
      
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
          
      @used_time += (Time.now - start_at).to_f
      recalculate_fps

	  @fps_text.string = "Zoom: #{zoom} FPS: #{@fps.round} [#{@potential_fps.round}]"
    end
    
    render do |win| 
      start_at = Time.now 
      
      win.with_view @camera do
        @map.draw_on(win, @camera.rect.y, @camera.rect.y + @camera.rect.height)  		

        #@visible_objects.each {|obj| obj.draw_shadow_on win }      
        #@visible_objects.each {|obj| obj.draw_on win }
      end
	  
	  win.draw @fps_text
      
      @used_time += (Time.now - start_at).to_f
    end
  end
  
  def init_fps
    @fps_next_calculated_at = Time.now.to_f + 1
    @fps = @potential_fps = 0
    @num_frames = 0
    @used_time = 0
  end
  
  def recalculate_fps
    @num_frames += 1
    
    if Time.now.to_f >= @fps_next_calculated_at     
      elapsed_time = @fps_next_calculated_at - Time.now.to_f + 1
      @fps = @num_frames / elapsed_time
      @potential_fps = @num_frames / [@used_time, 0.0001].max
       
      @num_frames = 0
      @fps_next_calculated_at = Time.now.to_f + 1
      @used_time = 0
    end
  end
end


Ray.game "2.5D" do
  register do
    on :quit, &method(:exit!)
    on :key_press, key(:escape), &method(:exit!)
  end
  
  scene_classes = [World]
  scene_classes.each {|s| s.bind(self) }
  scenes << :world
end
