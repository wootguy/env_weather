class PlayerState
{
	EHandle plr;
	bool exposed = false;
	float fogProgress = 0;
}

// persistent-ish player data, organized by steam-id or username if on a LAN server, values are @PlayerState
dictionary player_states;
bool debug_mode = false;
int effectCounter = 0;

string effect_sprite = "sprites/mommaspit.spr";


// Will create a new state if the requested one does not exit
PlayerState@ getPlayerState(CBasePlayer@ plr)
{
	string steamId = g_EngineFuncs.GetPlayerAuthId( plr.edict() );
	if (steamId == 'STEAM_ID_LAN' or steamId == 'BOT') {
		steamId = plr.pev.netname;
	}
	
	if ( !player_states.exists(steamId) )
	{
		PlayerState state;
		state.plr = plr;
		player_states[steamId] = state;
		println("ADDED STATE FOR: " + steamId);
	}
	return cast<PlayerState@>( player_states[steamId] );
}

void MapInit()
{	
	g_CustomEntityFuncs.RegisterCustomEntity( "env_weather", "env_weather1" );
	g_Game.PrecacheModel(effect_sprite);
}

void MapActivate()
{
	g_Scheduler.SetTimeout("populatePlayerStates", 2);
	g_Scheduler.SetTimeout("testSomething", 2);
}

// 
// 2, 20, 21, 23
// color: 17, 18, 19



void testSomething()
{
	
	
	g_Scheduler.SetTimeout("testSomething", 0.5);
}

void populatePlayerStates()
{	
	CBaseEntity@ ent = null;
	do {
		@ent = g_EntityFuncs.FindEntityByClassname(ent, "player"); 
		if (ent !is null)
		{
			CBasePlayer@ plr = cast<CBasePlayer@>(ent);
			getPlayerState(plr);
		}
	} while (ent !is null);
}

HookReturnCode ClientJoin(CBasePlayer@ plr)
{
	println("" + plr.pev.netname + " LE JOINED");
	getPlayerState(plr);
	return HOOK_CONTINUE;
}

HookReturnCode ClientLeave(CBasePlayer@ leaver)
{
	string steamId = g_EngineFuncs.GetPlayerAuthId( leaver.edict() );
	if (steamId == 'STEAM_ID_LAN') {
		steamId = leaver.pev.netname;
	}
		
	array<string>@ stateKeys = player_states.getKeys();
	for (uint i = 0; i < stateKeys.length(); i++)
	{
		PlayerState@ state = cast<PlayerState@>( player_states[stateKeys[i]] );
		CBaseEntity@ plr = state.plr;
		if (stateKeys[i] == steamId)
		{
			state.plr = null;
			break;
		}
	}
	player_states.delete(steamId);
	
	return HOOK_CONTINUE;
}

void impactSnow(CBaseEntity@ plr, Vector pos, int lifeTime, string spr)
{
	te_model(pos, Vector(0,0,0), 0, spr, 0, lifeTime, MSG_ONE_UNRELIABLE, plr.edict());
	incEffectCounter();
	g_Scheduler.SetTimeout("decEffectCounter", lifeTime*0.1f);
}

void incEffectCounter()
{
	effectCounter++;
}

void decEffectCounter()
{
	effectCounter--;
}

void snow(CBaseEntity@ plr, float fov, float radius, string spr, float speedMult)
{
	float c = Math.RandomFloat(0, fov) + plr.pev.v_angle.y*(Math.PI/180.0f) - fov*0.5f; // random point on circle
	float r = Math.RandomFloat(0.05, 1); // random radius
	float x = cos(c) * r * radius;
	float y = sin(c) * r * radius;
	float w = 0.2;
	Vector vel = Vector(Math.RandomFloat(-w, w),Math.RandomFloat(-w, w),-1);
	Vector dir = vel.Normalize();
	Vector offset = plr.pev.velocity*0.5f;
	
	// Don't spawn snow indoors
	Vector vecSrc = plr.pev.origin + Vector(x,y,Math.RandomFloat(64,600)) + offset;
	TraceResult tr;
	edict_t@ pEdict = g_EngineFuncs.PEntityOfEntIndex( 0 );
	string tex = g_Utility.TraceTexture( pEdict, vecSrc, vecSrc + Vector(0,0,1)*4096 );
	if (tex.ToLowercase() != "sky")
		return;
		
	incEffectCounter();
	
	te_projectile(vecSrc, vel*200*speedMult, null, spr, 4, MSG_ONE_UNRELIABLE, plr.edict());
	
	// spawn some stationary snow when the projectile snow hits a surface
	g_Utility.TraceLine( vecSrc, vecSrc + dir*4096, ignore_monsters, plr.edict(), tr );
	float dist = tr.flFraction * 4096;
	float speed = (vel*200*speedMult).Length();
	float delay = speed > 0 ? dist / speed : 0;
	Vector spawnOri = vecSrc + dir*dist;
	if (speed > 0)
		g_Scheduler.SetTimeout("impactSnow", delay, @plr, spawnOri, 8, spr);
	g_Scheduler.SetTimeout("decEffectCounter", delay);
	
	//te_streaksplash(plr.pev.origin + Vector(x,y,600), vel, 232, spawns, 2048, 32, MSG_ONE_UNRELIABLE, plr.edict());
}

void rain(CBaseEntity@ plr, float fov, float radius, int spawns)
{
	float c = Math.RandomFloat(0, fov) + plr.pev.v_angle.y*(Math.PI/180.0f) - fov*0.5f; // random point on circle
	float r = Math.RandomFloat(0.05, 1); // random radius
	float x = cos(c) * r * radius;
	float y = sin(c) * r * radius;
	Vector vel = Vector(0,0,-1);
	
	int rand = spawns > 1 ? 255 : 0;
	te_streaksplash(plr.pev.origin + Vector(x,y,600), vel, 232, spawns, 2048, rand, MSG_ONE_UNRELIABLE, plr.edict());
}

bool isPlayerExposed(CBaseEntity@ plr)
{
	Vector vecSrc = plr.pev.origin;
	TraceResult tr;
	edict_t@ pEdict = g_EngineFuncs.PEntityOfEntIndex( 0 );
	string tex = g_Utility.TraceTexture( pEdict, vecSrc, vecSrc + Vector(0,0,1)*4096 );
	return tex.ToLowercase() == "sky";
}

int snowCount = 0;
void weatherThink(EHandle h_settings)
{
	if (g_Engine.time < 2 or !h_settings)
		return;
		
	CBaseEntity@ settings_ent = h_settings;
	env_weather@ settings = cast<env_weather@>(CastToScriptClass(settings_ent));
		
	populatePlayerStates();
	array<string>@ stateKeys = player_states.getKeys();
	for (uint i = 0; i < stateKeys.length(); i++)
	{
		PlayerState@ state = cast<PlayerState@>( player_states[stateKeys[i]] );
		CBaseEntity@ plr = state.plr;
		
		CBasePlayer@ plrEnt = cast<CBasePlayer@>(plr);
		plrEnt.m_bloodColor = 242;
		
		int intensity = (int(g_Engine.time) % 19) - 2;
		//intensity = 18;
		//println("INTENSITY: " + intensity + " - " + ((intensity - 12)*2));
		//println("SPRITES: " + effectCounter);
		
		bool oldExposed = state.exposed;
		state.exposed = isPlayerExposed(plr);
		
		bool snowing = settings.weather_type == TYPE_SNOW;
		if (snowing)
		{					
			net_fog(settings.fogColor, settings.fogStart, settings.fogEnd, true, MSG_ONE_UNRELIABLE, plr.edict());
				
			for (int k = 0; k < settings.intensity; k++)
			{
				snow(plr, Math.PI*2.0f, settings.radius, settings.effect_sprite, settings.speedMult);
			}
		}
		else // rain
		{
			for (int k = 0; k < 20; k++)
			{
				if (intensity <= 0)
					break;
					
				if (intensity < 3)
				{
					if (intensity == 1 and snowCount % 4 != 0)
						break;
					if (intensity == 2 and snowCount % 2 != 0)
						break;
					rain(plr, Math.PI*1.5f, 1024, 1);
					break;
				}
				else if (intensity < 13)
				{
					if (k == (intensity-2)*2)
						break;
					rain(plr, Math.PI*1.5f, 1024, 1);
				}	
				else
					rain(plr, Math.PI*1.5f, 1024, (intensity - 12)*2);		
			}
		}
	}
	snowCount++;
}

enum weather_types
{
	TYPE_RAIN=1,
	TYPE_SNOW,
	TYPE_RAIN_STORM,
	TYPE_SANDSTORM,
	TYPE_BUBBLES,
	TYPE_FIRE,
	TYPE_SMOKE,
	TYPE_GLOWY_SPRITES,
	TYPE_HEADCRAB_STORM,
}

int FL_WEATHER_START_ON = 1;
int FL_WEATHER_CONSTANT_TRIGGER = 2;

class env_weather : ScriptBaseEntity
{	
	int weather_type;
	int intensity;
	float radius;
	float speedMult = 1.0f;
	Vector direction;
	string copy_fog_radius;
	
	Color fogColor;
	int fogStart;
	int fogEnd;
	
	Color fogColor2;
	int fogStart2;
	int fogEnd2;
	
	string effect_sprite;
	string exposed_trigger_target;
	string unexposed_trigger_target;
	float trigger_freq;
	
	bool KeyValue( const string& in szKey, const string& in szValue )
	{
		if (szKey == "vuser1") fogColor = parseColor(szValue);
		if (szKey == "vuser2") fogColor2 = parseColor(szValue);
		if (szKey == "iuser1") fogStart2 = atoi(szValue);
		if (szKey == "iuser2") fogEnd2 = atoi(szValue);
		
		return BaseClass.KeyValue( szKey, szValue );
	}
	
	void Spawn()
	{
		weather_type = pev.body;
		intensity = pev.skin;
		radius = pev.renderamt;
		direction = pev.rendercolor;
		copy_fog_radius = pev.noise;
		effect_sprite = pev.noise3;
		
		exposed_trigger_target = pev.noise1;
		unexposed_trigger_target = pev.noise2;
		trigger_freq = atof(pev.fuser1);
		speedMult = atof(pev.scale);
		
		fogStart = pev.rendermode;
		fogEnd = pev.renderfx;
		
		println("GOT C: " + fogColor.ToString());
	
		Precache();
		
		EHandle h_self = self;
		g_Scheduler.SetInterval("weatherThink", 0.05, -1, h_self);
	}
	
	void Precache()
	{
		//g_SoundSystem.PrecacheSound( sound );
		if (effect_sprite.Length() > 0)
			g_Game.PrecacheModel(effect_sprite);
	}
};


void print(string text) { g_Game.AlertMessage( at_console, text); }
void println(string text) { print(text + "\n"); }

void te_explosion(Vector pos, string sprite="sprites/zerogxplode.spr", int scale=10, int frameRate=15, int flags=0, NetworkMessageDest msgType=MSG_BROADCAST, edict_t@ dest=null) { NetworkMessage m(msgType, NetworkMessages::SVC_TEMPENTITY, dest);m.WriteByte(TE_EXPLOSION);m.WriteCoord(pos.x);m.WriteCoord(pos.y);m.WriteCoord(pos.z);m.WriteShort(g_EngineFuncs.ModelIndex(sprite));m.WriteByte(scale);m.WriteByte(frameRate);m.WriteByte(flags);m.End(); }
void te_sprite(Vector pos, string sprite="sprites/zerogxplode.spr", uint8 scale=10, uint8 alpha=200, NetworkMessageDest msgType=MSG_BROADCAST, edict_t@ dest=null) { NetworkMessage m(msgType, NetworkMessages::SVC_TEMPENTITY, dest);m.WriteByte(TE_SPRITE);m.WriteCoord(pos.x); m.WriteCoord(pos.y);m.WriteCoord(pos.z);m.WriteShort(g_EngineFuncs.ModelIndex(sprite));m.WriteByte(scale); m.WriteByte(alpha);m.End();}
void te_beampoints(Vector start, Vector end, string sprite="sprites/laserbeam.spr", uint8 frameStart=0, uint8 frameRate=100, uint8 life=1, uint8 width=2, uint8 noise=0, Color c=GREEN, uint8 scroll=32, NetworkMessageDest msgType=MSG_BROADCAST, edict_t@ dest=null) { NetworkMessage m(msgType, NetworkMessages::SVC_TEMPENTITY, dest);m.WriteByte(TE_BEAMPOINTS);m.WriteCoord(start.x);m.WriteCoord(start.y);m.WriteCoord(start.z);m.WriteCoord(end.x);m.WriteCoord(end.y);m.WriteCoord(end.z);m.WriteShort(g_EngineFuncs.ModelIndex(sprite));m.WriteByte(frameStart);m.WriteByte(frameRate);m.WriteByte(life);m.WriteByte(width);m.WriteByte(noise);m.WriteByte(c.r);m.WriteByte(c.g);m.WriteByte(c.b);m.WriteByte(c.a);m.WriteByte(scroll);m.End(); }
void te_bloodsprite(Vector pos, string sprite1="sprites/bloodspray.spr", string sprite2="sprites/blood.spr", uint8 color=70, uint8 scale=3, NetworkMessageDest msgType=MSG_BROADCAST, edict_t@ dest=null) { NetworkMessage m(msgType, NetworkMessages::SVC_TEMPENTITY, dest); m.WriteByte(TE_BLOODSPRITE);m.WriteCoord(pos.x);m.WriteCoord(pos.y);m.WriteCoord(pos.z);m.WriteShort(g_EngineFuncs.ModelIndex(sprite1));m.WriteShort(g_EngineFuncs.ModelIndex(sprite2));m.WriteByte(color);m.WriteByte(scale);m.End();}
void te_spritespray(Vector pos, Vector velocity, string sprite="sprites/bubble.spr", uint8 count=8, uint8 speed=16, uint8 noise=255, NetworkMessageDest msgType=MSG_BROADCAST, edict_t@ dest=null) { NetworkMessage m(msgType, NetworkMessages::SVC_TEMPENTITY, dest);m.WriteByte(TE_SPRITE_SPRAY);m.WriteCoord(pos.x);m.WriteCoord(pos.y);m.WriteCoord(pos.z);m.WriteCoord(velocity.x);m.WriteCoord(velocity.y);m.WriteCoord(velocity.z);m.WriteShort(g_EngineFuncs.ModelIndex(sprite));m.WriteByte(count);m.WriteByte(speed);m.WriteByte(noise);m.End(); }
void te_model(Vector pos, Vector velocity, float yaw=0, string model="models/agibs.mdl", uint8 bounceSound=2, uint8 life=32, NetworkMessageDest msgType=MSG_BROADCAST, edict_t@ dest=null) {NetworkMessage m(msgType, NetworkMessages::SVC_TEMPENTITY, dest);m.WriteByte(TE_MODEL);m.WriteCoord(pos.x);m.WriteCoord(pos.y);m.WriteCoord(pos.z);m.WriteCoord(velocity.x);m.WriteCoord(velocity.y);m.WriteCoord(velocity.z);m.WriteAngle(yaw);m.WriteShort(g_EngineFuncs.ModelIndex(model));m.WriteByte(bounceSound);m.WriteByte(life);m.End();}
void te_streaksplash(Vector start, Vector dir, uint8 color=250, uint16 count=256, uint16 speed=2048, uint16 speedNoise=128, NetworkMessageDest msgType=MSG_BROADCAST, edict_t@ dest=null) { NetworkMessage m(msgType, NetworkMessages::SVC_TEMPENTITY, dest);m.WriteByte(TE_STREAK_SPLASH);m.WriteCoord(start.x);m.WriteCoord(start.y);m.WriteCoord(start.z);m.WriteCoord(dir.x);m.WriteCoord(dir.y);m.WriteCoord(dir.z);m.WriteByte(color);m.WriteShort(count);m.WriteShort(speed);m.WriteShort(speedNoise);m.End(); }
void te_breakmodel(Vector pos, Vector size, Vector velocity, uint8 speedNoise=16, string model="models/hgibs.mdl", uint8 count=8, uint8 life=0, uint8 flags=20, NetworkMessageDest msgType=MSG_BROADCAST, edict_t@ dest=null) { NetworkMessage m(msgType, NetworkMessages::SVC_TEMPENTITY, dest);m.WriteByte(TE_BREAKMODEL);m.WriteCoord(pos.x);m.WriteCoord(pos.y);m.WriteCoord(pos.z);m.WriteCoord(size.x);m.WriteCoord(size.y);m.WriteCoord(size.z);m.WriteCoord(velocity.x);m.WriteCoord(velocity.y);m.WriteCoord(velocity.z);m.WriteByte(speedNoise);m.WriteShort(g_EngineFuncs.ModelIndex(model));m.WriteByte(count);m.WriteByte(life);m.WriteByte(flags);m.End(); }
void te_projectile(Vector pos, Vector velocity, CBaseEntity@ owner=null, string model="models/grenade.mdl", uint8 life=1, NetworkMessageDest msgType=MSG_BROADCAST, edict_t@ dest=null) {int ownerId = owner is null ? 0 : owner.entindex();NetworkMessage m(msgType, NetworkMessages::SVC_TEMPENTITY, dest);m.WriteByte(TE_PROJECTILE);m.WriteCoord(pos.x);m.WriteCoord(pos.y);m.WriteCoord(pos.z);m.WriteCoord(velocity.x);m.WriteCoord(velocity.y);m.WriteCoord(velocity.z);m.WriteShort(g_EngineFuncs.ModelIndex(model));m.WriteByte(life);m.WriteByte(ownerId);m.End();}
void te_firefield(Vector pos, uint16 radius=128, string sprite="sprites/grenade.spr", uint8 count=128, uint8 flags=30, uint8 life=5, NetworkMessageDest msgType=MSG_BROADCAST, edict_t@ dest=null) {NetworkMessage m(msgType, NetworkMessages::SVC_TEMPENTITY, dest);m.WriteByte(TE_FIREFIELD);m.WriteCoord(pos.x);m.WriteCoord(pos.y);m.WriteCoord(pos.z);m.WriteShort(radius);m.WriteShort(g_EngineFuncs.ModelIndex(sprite));m.WriteByte(count);m.WriteByte(flags);m.WriteByte(life);m.End();}

void net_fog(Color color, uint16 startDistance, uint16 endDistance, bool enabled=true, NetworkMessageDest msgType=MSG_BROADCAST, edict_t@ dest=null)
{
	NetworkMessage m(msgType, NetworkMessages::Fog, dest);
	
	// no idea what these params are for, but setting to 0 disables the fog
	m.WriteShort(0);
	m.WriteByte(enabled ? 1 : 0);
	
	// origin (unused)
	m.WriteCoord(0);
	m.WriteCoord(0);
	m.WriteCoord(0);
	
	m.WriteShort(0); // radius (unused)
	
	// RGB
	m.WriteByte(int8(color.r));
	m.WriteByte(int8(color.g));
	m.WriteByte(int8(color.b));

	m.WriteShort(startDistance); // start distance
	m.WriteShort(endDistance); // end distance
	
	m.End();
}

// convert output from Vector.ToString() back into a Vector
Vector parseVector(string s) {
	array<string> values = s.Split(" ");
	Vector v(0,0,0);
	if (values.length() > 0) v.x = atof( values[0] );
	if (values.length() > 1) v.y = atof( values[1] );
	if (values.length() > 2) v.z = atof( values[2] );
	return v;
}

// convert output from Vector.ToString() back into a Vector
Color parseColor(string s) {
	array<string> values = s.Split(" ");
	Color c(0,0,0,0);
	if (values.length() > 0) c.r = atoi( values[0] );
	if (values.length() > 1) c.g = atoi( values[1] );
	if (values.length() > 2) c.b = atoi( values[2] );
	if (values.length() > 3) c.a = atoi( values[3] );
	return c;
}

class Color
{ 
	uint8 r, g, b, a;
	Color() { r = g = b = a = 0; }
	Color(uint8 r, uint8 g, uint8 b) { this.r = r; this.g = g; this.b = b; this.a = 255; }
	Color(uint8 r, uint8 g, uint8 b, uint8 a) { this.r = r; this.g = g; this.b = b; this.a = a; }
	Color(float r, float g, float b, float a) { this.r = uint8(r); this.g = uint8(g); this.b = uint8(b); this.a = uint8(a); }
	Color (Vector v) { this.r = uint8(v.x); this.g = uint8(v.y); this.b = uint8(v.z); this.a = 255; }
	string ToString() { return "" + r + " " + g + " " + b + " " + a; }
	Vector getRGB() { return Vector(r, g, b); }
}

Color RED    = Color(255,0,0);
Color GREEN  = Color(0,255,0);
Color BLUE   = Color(0,0,255);
Color YELLOW = Color(255,255,0);
Color ORANGE = Color(255,127,0);
Color PURPLE = Color(127,0,255);
Color PINK   = Color(255,0,127);
Color TEAL   = Color(0,255,255);
Color WHITE  = Color(255,255,255);
Color BLACK  = Color(0,0,0);
Color GRAY  = Color(127,127,127);