local Interfaces = require("tests/interface_fixture")

local function expect(actual, expected, message)
    assert(actual == expected, message .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual))
end
local methods = {}
function methods:SetPos(x,y,xa,ya) self.x,self.y,self.xa,self.ya=x,y,xa or 0,ya or 0 end
function methods:SetSize(w,h,wa,ha) self.w,self.h,self.wa,self.ha=w,h,wa or 0,ha or 0 end
function methods:Subscribe(hook,name,callback)
    if callback == nil then callback,name=name,'default' end
    self.hooks[hook]=self.hooks[hook] or {};self.hooks[hook][name]=callback
end
function methods:Unsubscribe(hook,name) if self.hooks[hook] then self.hooks[hook][name]=nil end end
function methods:Emit(hook,...)
    for _,callback in pairs(self.hooks[hook] or {}) do if callback(self,...) == false then return false end end
    return true
end
function methods:Destroy() self.destroyed=true end
function methods:MoveToFront() end
local function factory(kind)
    return {new=function(parent,categoryID,dynamicID)
        local c={parent=parent,kind=kind,children={},hooks={},x=0,y=0,w=0,h=0,wa=0,ha=0}
        if parent then parent.children[#parent.children+1]=c end
        return Interfaces.component(setmetatable(c,{__index=function(self,key)
            if key=='width' then return self.w+(self.parent and self.parent.width or 0)*self.wa end
            if key=='height' then return self.h+(self.parent and self.parent.height or 0)*self.ha end
            return methods[key]
        end}), parent, categoryID, dynamicID)
    end}
end
ui={Hook={ONMOUSEOVER=1,ONMOUSEREPEAT=2,ONMOUSELEAVE=3,ONSCROLLWHEEL=4},AlignMode={TOPLEFT=0,CENTRE=1,BOTTOMRIGHT=2}}
for _,kind in ipairs({'Layer','Rectangle','Text','Sprite'}) do ui[kind]=factory(kind) end
id={Font={MUSEO_SANS_15PT_REGULAR=1,CINZEL_13PT_BOLD=2}}
config={Font={MUSEO_SANS_15PT_REGULAR={baseline=16,GetStringWidth=function(_,s)return #s*7 end,GetStringHeightAndLineCount=function()return 36 end}}}
package.loaded['src/core/sprites']={CONTENT_FRAME={},HUD_WINDOW={}}
local callbacks={}
Event={Logic={Subscribe=function(k,f)callbacks[k]=f end,Unsubscribe=function(k)callbacks[k]=nil end,
    Emit=function(tick)for _,f in pairs(callbacks) do f({logicTick=tick}) end end}}
local BarChart=require('src/bar_chart')
local Histogram=require('src/histogram')
local root=ui.Layer.new();root:SetSize(800,700)
local function hasVisibleText(component, text)
    if component.hidden or component.destroyed then return false end
    if component.kind=='Text' and component.content==text then return true end
    for _,child in ipairs(component.children) do
        if hasVisibleText(child,text) then return true end
    end
    return false
end
local rows={{id='a',label='Attack',value=120},{id='d',label='Defence',value=-40},{id='z',label='Zero',value=0}}
local wheel=0
local bar=BarChart.new(root,{label='XP by skill',data=rows,_onScrollWheel=function()wheel=wheel+1;return false end})
rows[1].value=999
expect(bar:GetSnapshot().data[1].value,120,'bar input is detached')
local snapshot=bar:GetSnapshot();snapshot.data[1].value=0
expect(bar:GetSnapshot().data[1].value,120,'bar snapshot is detached')
assert(bar.bars[1].x>=bar.baseline.x and bar.bars[2].x<bar.baseline.x,'signed horizontal bars straddle zero')
assert(bar.plotWidth>=bar.root.width-2,'horizontal plot fills the frame without a label gutter')
assert(not hasVisibleText(bar.root,'Attack') and not hasVisibleText(bar.root,'Defence'),
    'category names are absent until hover')
bar.plot:Emit(ui.Hook.ONMOUSEOVER,bar.plotWidth-1,bar.edges[2]/2)
assert(bar.tooltip.label.content:find('Attack',1,true),'hover identifies the category across its entire row')
expect(bar.highlight.hidden,false,'hover shows the row highlight')
expect(bar.highlight.width,bar.plotWidth,'horizontal highlight spans the full plot width')
expect(bar.highlight.height,bar.edges[2]-bar.edges[1],'horizontal highlight covers one complete row')
expect(pcall(bar.SetData,bar,{[1]=rows[1],[3]=rows[2]}),false,'sparse data is rejected')
expect(bar:GetSnapshot().data[1].value,120,'invalid replacement leaves bar data unchanged')
bar.plot:Emit(ui.Hook.ONMOUSEOVER,10,bar.plotHeight*2.5/3)
assert(bar.tooltip.label.content:find('Zero',1,true) and bar.tooltip.label.content:find('<br>0',1,true),'zero category remains hoverable')
expect(bar.highlight.y,bar.plotY+bar.edges[3],'highlight follows the zero-valued row')
local tooltipX=bar.tooltip.root.x
bar.plot:Emit(ui.Hook.ONMOUSEREPEAT,15,bar.plotHeight*2.5/3)
assert(bar.tooltip.root.x~=tooltipX,'tooltip follows the pointer')
expect(bar.plot:Emit(ui.Hook.ONSCROLLWHEEL,1),false,'chart leaves wheel ownership with host')
expect(wheel,1,'chart wheel reaches host once')
bar.plot:Emit(ui.Hook.ONMOUSELEAVE)
expect(bar.highlight.hidden,true,'leaving the plot clears the highlight')
expect(bar.tooltip.root.hidden,true,'leaving the plot clears the tooltip')
bar.plot:Emit(ui.Hook.ONMOUSEOVER,10,bar.plotHeight/2)
bar:SetVisible(false)
expect(bar.tooltip.root.hidden,true,'hiding chart hides tooltip')
expect(bar.highlight.hidden,true,'hiding chart clears the highlight')
bar:SetVisible(true)
bar.plot:Emit(ui.Hook.ONMOUSEOVER,10,bar.plotHeight/2)
bar.plot:Emit(ui.Hook.ONMOUSEREPEAT,bar.plotWidth,bar.plotHeight/2)
expect(bar.highlight.hidden,true,'right plot boundary is outside hover coverage')
bar.plot:Emit(ui.Hook.ONMOUSEOVER,10,bar.plotHeight/2)
bar:SetData({})
expect(bar.empty.hidden,false,'empty replacement has an explicit empty state')
expect(bar.tooltip.root.hidden,true,'replacement clears stale hover')
expect(bar.highlight.hidden,true,'replacement clears stale highlight')
local vertical=BarChart.new(root,{orientation='vertical',data={{id='p',label='Gain',value=5},{id='n',label='Loss',value=-2}}})
assert(vertical.bars[1].y<vertical.baseline.y and vertical.bars[2].y>=vertical.baseline.y,'signed vertical bars straddle zero')
assert(vertical.plotWidth>=vertical.root.width-2,'vertical plot fills the frame')
vertical.plot:Emit(ui.Hook.ONMOUSEOVER,vertical.edges[2],10)
assert(vertical.tooltip.label.content:find('Loss',1,true),'exact category boundary selects the next bar')
expect(vertical.highlight.x,vertical.plotX+vertical.edges[2],'vertical highlight follows selected column')
expect(vertical.highlight.width,vertical.edges[3]-vertical.edges[2],'vertical highlight covers one column')
expect(vertical.highlight.height,vertical.plotHeight,'vertical highlight spans the full plot height')
local skillRows, skillColours, usedColours = {}, {}, {}
for skill = 0, 28 do
    skillRows[#skillRows+1] = {id=tostring(skill),label='Skill '..skill,value=skill+1}
end
local coloured=BarChart.new(root,{data=skillRows})
for index,row in ipairs(skillRows) do
    local rgba=coloured.bars[index].rgba
    assert(not usedColours[rgba],'different skills receive different colours')
    skillColours[row.id],usedColours[rgba]=rgba,true
end
local reordered={}
for index=#skillRows,1,-1 do
    local row=skillRows[index]
    reordered[#reordered+1]={id=row.id,label='Renamed '..row.label,value=-row.value}
end
coloured:SetData(reordered)
for index,row in ipairs(reordered) do
    expect(coloured.bars[index].rgba,skillColours[row.id],'colour follows source ID, not rank, label or sign')
end
coloured:Reset()
coloured:SetData(skillRows)
local secondView=BarChart.new(root,{orientation='vertical',data=reordered})
for index,row in ipairs(reordered) do
    expect(secondView.bars[index].rgba,skillColours[row.id],'independent views retain source colours')
end
for index,row in ipairs(skillRows) do
    expect(coloured.bars[index].rgba,skillColours[row.id],'reset retains source colours')
end
local override=BarChart.new(root,{rgba=0x112233FF,data={
    {id='0',label='Attack',value=1},{id='1',label='Defence',value=2,rgba=0xAABBCCFF}}})
expect(override.bars[1].rgba,0x112233FF,'chart colour overrides generated colours')
expect(override.bars[2].rgba,0xAABBCCFF,'row colour overrides chart colour')
override:SetData({{id='2',label='Strength',value=3}})
expect(override.bars[1].rgba,0x112233FF,'replacement retains explicit chart colour')
local histogram=Histogram.new(root,{label='Kill seconds',binWidth=5})
local samples={-5,0,4.999,5,15}
histogram:SetSamples(samples)
samples[1]=100
local bins=histogram:GetSnapshot().bins
expect(bins[1].lower,-5,'negative samples use floor-based bins')
expect(bins[1].count,1,'negative exact boundary belongs to following interval')
expect(bins[2].count,2,'lower-inclusive upper-exclusive bin groups fractional samples')
expect(bins[3].count,1,'exact positive boundary enters next bin')
expect(bins[4].count,0,'intervening empty bins are retained')
expect(bins[5].count,1,'highest exact boundary starts a bin')
expect(histogram:GetSnapshot().sampleCount,5,'sample count is not affected by caller mutation')
bins[1].count=0
expect(histogram:GetSnapshot().bins[1].count,1,'histogram snapshot is detached')
assert(histogram.plotWidth>=histogram.root.width-2,'histogram fills the frame without an axis gutter')
histogram.plot:Emit(ui.Hook.ONMOUSEOVER,(histogram.edges[4]+histogram.edges[5])/2,10)
assert(histogram.tooltip.label.content:find('Count: 0',1,true),'empty histogram bin remains hoverable')
expect(histogram.highlight.hidden,false,'empty bins retain a visible highlight')
expect(histogram.highlight.height,histogram.plotHeight,'histogram highlight spans the full plot height')
histogram.plot:Emit(ui.Hook.ONMOUSEREPEAT,histogram.edges[5],10)
assert(histogram.tooltip.label.content:find('[15, 20)',1,true),'pixel boundary hover selects the following bin')
histogram:SetBins({{lower=0,upper=1,count=1},{lower=1,upper=10,count=3}})
assert(histogram.bars[2].width>histogram.bars[1].width*6,'explicit unequal bin widths are drawn proportionally')
histogram.plot:Emit(ui.Hook.ONMOUSEOVER,histogram.edges[2],10)
expect(histogram.highlight.width,histogram.edges[3]-histogram.edges[2],'highlight respects unequal bin widths')
expect(histogram:GetSnapshot().sampleCount,4,'explicit bins supply total count')
expect(pcall(histogram.SetBins,histogram,{{lower=0,upper=1,count=1},{lower=2,upper=3,count=2}}),false,'discontiguous bins are rejected')
expect(histogram:GetSnapshot().sampleCount,4,'invalid bins leave the previous distribution intact')
histogram:SetSamples({0,5115})
expect(#histogram:GetSnapshot().bins,1024,'inclusive 1024-bin span is supported')
expect(pcall(histogram.SetSamples,histogram,{0,5120}),false,'oversized gap span is rejected before allocation')
expect(histogram:GetSnapshot().sampleCount,2,'oversized replacement is atomic')
expect(pcall(histogram.SetSamples,histogram,{0/0}),false,'nonfinite samples are rejected')
histogram:Reset()
expect(histogram:GetSnapshot().sampleCount,0,'reset clears the distribution')
histogram:SetSamples({-5,0})
expect(histogram:GetSnapshot().bins[1].upper,0,'reset retains sampling configuration')
local anchored=BarChart.new(root,{width=-20,widthAnchor=1,data={{id='x',label='X',value=1}}})
local oldWidth=anchored.plotWidth
root:SetSize(900,700);Event.Logic.Emit(1)
assert(anchored.plotWidth>oldWidth,'native anchor changes update chart geometry')
anchored.plot:Emit(ui.Hook.ONMOUSEOVER,10,10)
anchored:SetSize(1,1)
expect(anchored.highlight.hidden,true,'resizing clears stale hover geometry')
for _,rectangle in ipairs(anchored.bars) do assert(rectangle.width>=0 and rectangle.height>=0,'tiny geometry never produces negative dimensions') end
local tooltipSurface=histogram.tooltip.root
BarChart.Shutdown();Histogram.Shutdown()
expect(tooltipSurface.destroyed,true,'shutdown removes tooltip surfaces')
expect(next(callbacks),nil,'shutdown removes chart resize subscriptions')
expect(histogram:SetSamples({1}),false,'destroyed chart rejects updates')
expect(histogram:GetSnapshot().sampleCount,2,'snapshots remain usable after destruction')
print('charts_test: full-width geometry, hover-only categories, whole-slot highlights, stable colours, ownership, binning, atomic rejection, resize and lifecycle passed')
