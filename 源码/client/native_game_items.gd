extends Window
## Original Game Item window's three tabs, implemented locally instead of
## depending on the original unavailable embedded web pages.
signal buy_requested(item: int, slot: int)
signal sell_requested(slot: int)
var catalog: Dictionary = {}
var profile: Dictionary = {}
var tabs: TabContainer
var inventory: VBoxContainer
var shop: Control
var balance: Label
var profile_stamp:=""

func _ready() -> void:
	title="游戏道具"
	name="NativeGameItems"
	exclusive=true
	transient=true
	min_size=Vector2i(680,400)
	close_requested.connect(queue_free)
	var background:=TextureRect.new()
	background.texture=load("res://assets/legacy/gameitem/GameItemBack.png")
	background.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margin:=MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+side,10)
	add_child(margin)
	var body:=VBoxContainer.new()
	margin.add_child(body)
	tabs=TabContainer.new()
	tabs.name="GameItemTabs"
	tabs.size_flags_vertical=Control.SIZE_EXPAND_FILL
	tabs.add_theme_stylebox_override("panel",preload("res://original_skin.gd").box(Color.WHITE,Color("7090a8")))
	for state in ["unselected","selected","hovered"]:
		tabs.add_theme_stylebox_override("tab_"+state,preload("res://original_skin.gd").box(Color.WHITE if state=="selected" else Color("dce5ed"),Color("7090a8")))
	for state in ["selected","unselected","hovered"]:tabs.add_theme_color_override("font_"+state+"_color",Color.BLACK)
	body.add_child(tabs)
	var help:=RichTextLabel.new()
	help.name="帮助"
	help.add_theme_color_override("default_color",Color.BLACK)
	help.add_theme_font_size_override("normal_font_size",16)
	help.text="游戏道具\n\n在“购买物品”中选择道具，再点购买。每位玩家最多携带四件道具，空槽会按顺序填入；也可在商店选择指定空槽。\n\n“我的商品”显示当前携带的道具。对局内按 F5、F6、F7、F8，或点击对应道具使用。投掷道具需要随后瞄准、蓄力并发射。\n\n小补给不结束行动；大补给、团队补给、超级燃料箱使用后结束本次行动。双发不作用于必杀技。\n\n在购买页选中已携带道具，可以按半价出售。对战期间不能购买或出售，金币和背包由服务器保存。"
	tabs.add_child(help)
	var owned:=ScrollContainer.new()
	owned.name="我的商品"
	tabs.add_child(owned)
	inventory=VBoxContainer.new()
	inventory.name="OwnedItems"
	inventory.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	inventory.add_theme_constant_override("separation",12)
	owned.add_child(inventory)
	var purchase:=AspectRatioContainer.new()
	purchase.name="购买物品"
	purchase.ratio=800.0/307
	tabs.add_child(purchase)
	shop=preload("res://native_shop.gd").new()
	shop.name="GameItemPurchase"
	shop.catalog=catalog
	shop.profile=profile
	shop.buy_requested.connect(func(item:int,slot:int):buy_requested.emit(item,slot))
	shop.sell_requested.connect(func(slot:int):sell_requested.emit(slot))
	purchase.add_child(shop)
	var footer:=HBoxContainer.new()
	body.add_child(footer)
	balance=Label.new()
	balance.add_theme_color_override("font_color",Color.BLACK)
	balance.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	footer.add_child(balance)
	var close:=Button.new()
	close.text="关闭"
	close.custom_minimum_size=Vector2(90,32)
	close.pressed.connect(queue_free)
	footer.add_child(close)
	set_profile(profile)

func set_profile(value:Dictionary) -> void:
	profile=value
	if not is_instance_valid(inventory):return
	var stamp:=JSON.stringify([profile.get("inventory",[]),profile.get("gold",0)])
	if stamp==profile_stamp:return
	profile_stamp=stamp
	shop.set_profile(profile)
	balance.text="金币：%d G"%int(profile.get("gold",0))
	for child in inventory.get_children():
		child.hide()
		child.queue_free()
	var carried:Array=profile.get("inventory",[0,0,0,0])
	for index in range(4):
		var row:=HBoxContainer.new()
		row.custom_minimum_size.y=70
		inventory.add_child(row)
		var key:=Label.new()
		key.text="F%d"%(5+index)
		key.add_theme_color_override("font_color",Color.BLACK)
		row.add_child(key)
		var icon:=TextureRect.new()
		icon.custom_minimum_size=Vector2(48,48)
		icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)
		var description:=Label.new()
		description.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		description.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		description.add_theme_color_override("font_color",Color.BLACK)
		description.text="空槽"
		row.add_child(description)
		var id:=int(carried[index])
		if id>0:
			icon.texture=load("res://assets/icons/ItemIcon/%02d.png"%id)
			for item:Dictionary in catalog.get("items",[]):
				if int(item.id)==id:description.text=str(item.name)+"\n"+str(item.description)

func _unhandled_key_input(event:InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.physical_keycode==KEY_ESCAPE:
		queue_free()
		set_input_as_handled()
