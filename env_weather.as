class PlayerState
{
	EHandle plr;
	bool exposed = false;
	
	FogSettings currentFog;
	FogSettings targetFog;
	
	float fogInterp = 0;
	bool transitionFinished = false;
	int fogInterpMode = EASE_OUT;
	
	float lastFogTouch = -1;
	int lastFogTouchId = 0;
	
	int particleCounter = 0;
	
	FogSettings getInterpolatedFog()
	{
		FogSettings ret;
		
		float p = fogInterp;
		float z = p;
		float q = 1.0f - p;
		
		switch(fogInterpMode)
		{
			case EASE_IN:          p = p*p*p;                     break;
			case EASE_OUT:         p = 1.0f - q*q*q;              break;
		}
		
		
		{	// color interp
			Color A = currentFog.color;
			Color B = targetFog.color;
			int dr = int( float( int(B.r) - int(A.r) )*p + 0.5 );
			int dg = int( float( int(B.g) - int(A.g) )*p + 0.5 );
			int db = int( float( int(B.b) - int(A.b) )*p + 0.5 );
			int da = int( float( int(B.a) - int(A.a) )*p + 0.5 );
			ret.color = Color(A.r + dr, A.g + dg, A.b + db, A.a + da);
		}
		
		{	// start interp
			int a = currentFog.start;
			int b = targetFog.start;
			int d = int( int(b - a)*p + 0.5 );
			ret.start = a + d;
		}
		
		{	// end interp
			if (fogInterpMode == EASE_IN)
				p = z;
			int a = currentFog.end;
			int b = targetFog.end;
			int d = int( int(b - a)*p + 0.5 );
			ret.end = a + d;
		}
		
		return ret;
	}
	
	void setNewFogTarget(FogSettings fog)
	{
		currentFog = getInterpolatedFog();
		fogInterp = 0;
		transitionFinished = false;
		
		targetFog.color = fog.color;
		targetFog.start = fog.start;
		targetFog.end = fog.end;
	}
	
	void setDefaultFogTarget()
	{
		FogSettings fog = default_fog;
		fogInterpMode = EASE_OUT;
		if (no_default_fog)
		{
			fog = getInterpolatedFog();
			fog.end = 32767;
			fog.start = 32766;
			fogInterpMode = EASE_IN;
		}
		
		transitionFinished = false;
		setNewFogTarget(fog);
		
		if (lastFogTouch < 0)
			fogInterp = 1.0f;
			
		lastFogTouch = 0;
		lastFogTouchId = 0;
	}
}

class FogSettings
{
	Color color;
	int start = 0;
	int end = 65535;
}

enum fog_interps
{
	EASE_IN,
	EASE_OUT
}

// persistent-ish player data, organized by steam-id or username if on a LAN server, values are @PlayerState
dictionary player_states;
bool debug_mode = false;

FogSettings default_fog;
bool no_default_fog = true;

// Will create a new state if the requested one does not exit
PlayerState@ getPlayerState(CBasePlayer@ plr)
{
	if (plr is null)
		return null;
		
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
		g_Scheduler.SetTimeout("initFog", 0.5, steamId);
	}
	return cast<PlayerState@>( player_states[steamId] );
}

void initFog(string key)
{	
	PlayerState@ state = cast<PlayerState@>( player_states[key] );
	if (state is null)
		println("OH NOOO");
		
	state.transitionFinished = false;
	state.fogInterp = 1;
	println("WHY NO WORK");
}

void WeatherMapInit()
{	
	player_states.deleteAll();
	g_CustomEntityFuncs.RegisterCustomEntity( "env_weather", "env_weather1" );
	g_CustomEntityFuncs.RegisterCustomEntity( "func_fog", "func_fog" );
}

void WeatherMapActivate()
{
	g_Scheduler.SetTimeout("populatePlayerStates", 2);
	g_Scheduler.SetInterval("fogThink", 0.05);
	scanForFogFadeEnts();
}

array<EHandle> fogFadeEnts;
void scanForFogFadeEnts()
{	
	fogFadeEnts.resize(0);
	CBaseEntity@ ent = null;
	do {
		@ent = g_EntityFuncs.FindEntityByClassname(ent, "*"); 
		if (ent !is null and ent.pev.rendermode == 123)
		{
			EHandle h_ent = ent;
			ent.pev.rendermode = 2;
			fogFadeEnts.insertLast(h_ent);
		}
	} while (ent !is null);
}

HookReturnCode ClientJoin(CBasePlayer@ plr)
{
	println("" + plr.pev.netname + " LE JOINED");
	getPlayerState(plr);
	return HOOK_CONTINUE;
}

void test(CBaseEntity@ ent)
{
	println("WOW" + ent.pev.classname);
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

void fogThink()
{
	array<string>@ stateKeys = player_states.getKeys();
	for (uint i = 0; i < stateKeys.length(); i++)
	{
		PlayerState@ state = cast<PlayerState@>( player_states[stateKeys[i]] );
		CBaseEntity@ plr = state.plr;
		
		if (!state.transitionFinished)
		{
			FogSettings fog = state.getInterpolatedFog();
			bool enabled = true;
			
			if (state.fogInterp < 1.0f)
				state.fogInterp += 0.05f;
			if (state.fogInterp >= 1.0f)
			{
				if (state.lastFogTouchId == 0 and no_default_fog)
					enabled = false;
				state.transitionFinished = true;
				state.fogInterp = 1.0f;
				fog = state.targetFog;
			}

			println("SEND FOG TO: " + plr.pev.netname);
			net_fog(fog.color, fog.start, fog.end, enabled, MSG_ONE_UNRELIABLE, plr.edict());
		}
		
		if (state.lastFogTouch < 0 or (state.lastFogTouch > 0 and (g_Engine.time - state.lastFogTouch) > 0.1f))
		{
			state.setDefaultFogTarget();
		}
		
		for (uint k = 0; k < fogFadeEnts.length(); k++)
		{
			CBaseEntity@ ent = fogFadeEnts[k];
			println("GOT FADE ENT: " + ent.pev.classname);
			
			Vector pos = ent.pev.origin + Vector(0,100,0);
			//te_model(pos, Vector(0,0,0), 0, ent.pev.model, 0, 8, MSG_ONE_UNRELIABLE, plr.edict());
			//te_bubbletrail(pos, pos, ent.pev.model, 16, 1, -0.0f, MSG_ONE_UNRELIABLE, plr.edict());
		}
	}
	
	
}

void impactSnow(PlayerState@ state, Vector pos, int lifeTime, string spr)
{
	CBaseEntity@ plr = state.plr;
	// if we're close to the limit, don't spawn impact sprites that aren't immediately next to us
	//println("PARTICLES: " + state.particleCounter);
	if (state.particleCounter >= 500)
	{
		println("WEATHER SPRITE OVERFLOW! REDUCE YOUR WEATHER INTENSITY!");
		return; // don't go over this limit!
	}
		
	//te_sprite(pos, spr, 5, 200, MSG_ONE_UNRELIABLE, plr.edict());
	te_model(pos + Vector(0,0,1), Vector(0,0,0), 0, spr, 0, lifeTime, MSG_ONE_UNRELIABLE, plr.edict());
	incParticleCounter(state);
	g_Scheduler.SetTimeout("decParticleCounter", lifeTime*0.1f, @state);
}

void incParticleCounter(PlayerState@ state)
{
	state.particleCounter++;
}

void decParticleCounter(PlayerState@ state)
{
	state.particleCounter--;
}

void snow(PlayerState@ state, float fov, float radius, string spr, float speedMult, Vector angles)
{
	float maxSnowDist = 16384;
	CBaseEntity@ plr = state.plr;
	if (state.particleCounter >= 500)
	{
		println("WEATHER SPRITE OVERFLOW! REDUCE YOUR WEATHER INTENSITY!");
		return;
	}
		
	float c = Math.RandomFloat(0, fov) + plr.pev.v_angle.y*(Math.PI/180.0f) - fov*0.5f; // random point on circle
	float r = Math.RandomFloat(0, 1); // random radius
	float x = cos(c) * r * radius;
	float y = sin(c) * r * radius;
	
	Math.MakeVectors(angles);
	Vector vel = g_Engine.v_forward;
	vel = spreadDir(vel, 30);
	Vector dir = vel.Normalize();
	Vector angleOffset = g_Engine.v_forward*-600;
	angleOffset.z = 0;
	Vector offset = plr.pev.velocity*0.5f + angleOffset;
	
	float height = Math.RandomFloat(64, 1200);		
	Vector vecSrc = plr.pev.origin + Vector(x,y,height) + offset;
	
	// Don't spawn snow indoors
	TraceResult tr;
	Vector checkDir = g_Engine.v_forward*-maxSnowDist;
	g_Utility.TraceLine( vecSrc, vecSrc + checkDir, ignore_monsters, plr.edict(), tr );
	CBaseEntity@ pHit = g_EntityFuncs.Instance( tr.pHit );
	if (tr.flFraction >= 1.0f or (pHit !is null and pHit.pev.classname != "worldspawn"))
		return;
	
	edict_t@ pEdict = g_EngineFuncs.PEntityOfEntIndex( 0 );
	string tex = g_Utility.TraceTexture( pEdict, vecSrc, vecSrc + checkDir );
	if (tex.ToLowercase() != "sky")
		return;
		
	//te_beampoints(vecSrc, vecSrc + g_Engine.v_forward*-512);
		
	incParticleCounter(state);
	
	// spawn some stationary snow when the projectile snow hits a surface
	g_Utility.TraceLine( vecSrc, vecSrc + dir*maxSnowDist, ignore_monsters, plr.edict(), tr );
	@pHit = g_EntityFuncs.Instance( tr.pHit );
	float dist = tr.flFraction * maxSnowDist;
	float speed = (vel*200*speedMult).Length();
	float delay = speed > 0 ? dist / speed : 0;
	bool tooHigh = false;
	if (delay > 1.6f) {
		delay = 1.6f;
		tooHigh = true;
	}
	
	Vector spawnOri = vecSrc + dir*dist;
	int lifeTime = 8;
	if (pHit !is null and pHit.pev.classname != "worldspawn" or abs(tr.vecPlaneNormal.z) < 0.5f)
		lifeTime = 2;
	if (speed > 0 && !tooHigh)
		g_Scheduler.SetTimeout("impactSnow", delay, @state, spawnOri, lifeTime, spr);
	g_Scheduler.SetTimeout("decParticleCounter", delay, @state);
	
	te_projectile(vecSrc, vel*200*speedMult, null, spr, int(delay+1), MSG_ONE_UNRELIABLE, plr.edict());
	
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
	te_streaksplash(plr.pev.origin + Vector(x,y,600), vel, 7, spawns, 2048, rand, MSG_ONE_UNRELIABLE, plr.edict());
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
	
	if (!settings.active)
		return;
		
	populatePlayerStates();
	array<string>@ stateKeys = player_states.getKeys();
	for (uint i = 0; i < stateKeys.length(); i++)
	{
		PlayerState@ state = cast<PlayerState@>( player_states[stateKeys[i]] );
		CBaseEntity@ plr = state.plr;
		
		int intensity = (int(g_Engine.time) % 19) - 2;
		intensity = 1;
		//println("INTENSITY: " + intensity + " - " + ((intensity - 12)*2));
		//println("SPRITES: " + effectCounter);
		
		bool oldExposed = state.exposed;
		state.exposed = isPlayerExposed(plr);
		
		bool snowing = settings.weather_type == TYPE_SNOW;
		if (snowing)
		{					
			for (int k = 0; k < settings.intensity; k++)
			{
				snow(state, Math.PI*2.0f, settings.radius, settings.effect_sprite, settings.speedMult, settings.pev.angles);
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
	
	FogSettings fog;
	
	string effect_sprite;
	string exposed_trigger_target;
	string unexposed_trigger_target;
	float trigger_freq;
	
	bool active = true;
	
	bool KeyValue( const string& in szKey, const string& in szValue )
	{
		if (szKey == "fog_color") fog.color = parseColor(szValue);
		else if (szKey == "weather_type") weather_type = atoi(szValue);
		else if (szKey == "intensity") intensity = atoi(szValue);
		else if (szKey == "radius") radius = atof(szValue);
		else if (szKey == "particle_spr") effect_sprite = szValue;
		else if (szKey == "exposed_trig") exposed_trigger_target = szValue;
		else if (szKey == "unexposed_trig") unexposed_trigger_target = szValue;
		else if (szKey == "trig_freq") trigger_freq = atof(szValue);
		else if (szKey == "speed_mult") speedMult = atof(szValue);
		else if (szKey == "fog_start") fog.start = atoi(szValue);
		else if (szKey == "fog_end") fog.end = atoi(szValue);
		else return BaseClass.KeyValue( szKey, szValue );
		
		return true;
	}
	
	void Spawn()
	{			
		Precache();
		
		EHandle h_self = self;
		g_Scheduler.SetInterval("weatherThink", 0.05, -1, h_self);
		
		default_fog = fog;
		no_default_fog = false;
		
		active = pev.spawnflags & FL_WEATHER_START_ON != 0;
	}
	
	void Precache()
	{
		//g_SoundSystem.PrecacheSound( sound );
		if (effect_sprite.Length() > 0)
			g_Game.PrecacheModel(effect_sprite);
	}
	
	void Use(CBaseEntity@ pActivator, CBaseEntity@ pCaller, USE_TYPE useType, float flValue = 0.0f)
	{
		if (useType == USE_ON)
			active = true;
		if (useType == USE_OFF)
			active = false;
		else
			active = !active;
			
		no_default_fog = !active;
			
		// clear fog for anyone outdoors
		array<string>@ stateKeys = player_states.getKeys();
		for (uint i = 0; i < stateKeys.length(); i++)
		{
			PlayerState@ state = cast<PlayerState@>( player_states[stateKeys[i]] );
			CBaseEntity@ plr = state.plr;
			
			if (state.lastFogTouchId == 0)
				state.setDefaultFogTarget();
		}
		
	}
};


class func_fog : ScriptBaseEntity
{		
	FogSettings fog;
	float transitionTime;
	bool active;
	
	bool KeyValue( const string& in szKey, const string& in szValue )
	{		
		if (szKey == "fog_color") fog.color = parseColor(szValue);
		else if (szKey == "fog_start") fog.start = atoi(szValue);
		else if (szKey == "fog_end") fog.end = atoi(szValue);
		else if (szKey == "renderamt") transitionTime = atof(szValue);
		else return BaseClass.KeyValue( szKey, szValue );
		
		return true;
	}
	
	void Spawn()
	{				
		self.pev.solid = SOLID_TRIGGER;
		self.pev.movetype = MOVETYPE_NONE;
		self.pev.effects = EF_NODRAW;
		
		g_EntityFuncs.SetModel(self, self.pev.model);
		g_EntityFuncs.SetSize(self.pev, self.pev.mins, self.pev.maxs);
		g_EntityFuncs.SetOrigin(self, self.pev.origin);
		
		active = pev.spawnflags & FL_WEATHER_START_ON != 0;
	}
	
	void Touch( CBaseEntity@ pOther )
	{
		if (!active or !pOther.IsPlayer())
			return;
		CBasePlayer@ plr = cast<CBasePlayer@>(pOther);
		PlayerState@ state = getPlayerState(plr);
		
		state.lastFogTouch = g_Engine.time;
		
		if (state.lastFogTouchId == self.entindex())
			return;
		
		state.setNewFogTarget(fog);
		state.lastFogTouchId = self.entindex();
		state.fogInterpMode = EASE_OUT;
	}
	
	void Use(CBaseEntity@ pActivator, CBaseEntity@ pCaller, USE_TYPE useType, float flValue = 0.0f)
	{
		if (useType == USE_ON)
			active = true;
		if (useType == USE_OFF)
			active = false;
		else
			active = !active;
			
		// clear fog for anyone outdoors
		array<string>@ stateKeys = player_states.getKeys();
		for (uint i = 0; i < stateKeys.length(); i++)
		{
			PlayerState@ state = cast<PlayerState@>( player_states[stateKeys[i]] );
			CBaseEntity@ plr = state.plr;
			
			if (state.lastFogTouchId == self.entindex())
				state.setDefaultFogTarget();
		}
		
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
void te_bubbletrail(Vector start, Vector end, string sprite="sprites/bubble.spr", float height=128.0f, uint8 count=16, float speed=16.0f, NetworkMessageDest msgType=MSG_BROADCAST, edict_t@ dest=null) { NetworkMessage m(msgType, NetworkMessages::SVC_TEMPENTITY, dest);m.WriteByte(TE_BUBBLETRAIL);m.WriteCoord(start.x);m.WriteCoord(start.y);m.WriteCoord(start.z);m.WriteCoord(end.x);m.WriteCoord(end.y);m.WriteCoord(end.z);m.WriteCoord(height);m.WriteShort(g_EngineFuncs.ModelIndex(sprite));m.WriteByte(count);m.WriteCoord(speed);m.End(); }

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

// Randomize the direction of a vector by some amount
// Max degrees = 360, which makes a full sphere
Vector spreadDir(Vector dir, float degrees)
{
	float spread = Math.DegreesToRadians(degrees) * 0.5f;
	float x, y;
	Vector vecAiming = dir;

	float c = Math.RandomFloat(0, Math.PI*2); // random point on circle
	float r = Math.RandomFloat(-1, 1); // random radius
	x = cos(c) * r * spread;
	y = sin(c) * r * spread;
	
	// get "up" vector relative to aim direction
	Vector up = Vector(0, 0, 1);
	if (abs(dir.z) > 0.9)
		up = Vector(1, 0, 0);
	Vector pitAxis = CrossProduct(dir, up).Normalize(); // get left vector of aim dir
	Vector yawAxis = CrossProduct(dir, pitAxis).Normalize(); // get up vector relative to aim dir
	
	// Apply rotation around arbitrary "up" axis
	array<float> yawRotMat = rotationMatrix(yawAxis, x);
	vecAiming = matMultVector(yawRotMat, vecAiming).Normalize();
	
	// Apply rotation around "left/right" axis
	array<float> pitRotMat = rotationMatrix(pitAxis, y);
	vecAiming = matMultVector(pitRotMat, vecAiming).Normalize();
			
	return vecAiming;
}

array<float> rotationMatrix(Vector axis, float angle)
{
	axis = axis.Normalize();
    float s = sin(angle);
    float c = cos(angle);
    float oc = 1.0 - c;
 
	array<float> mat = {
		oc * axis.x * axis.x + c,          oc * axis.x * axis.y - axis.z * s, oc * axis.z * axis.x + axis.y * s, 0.0,
		oc * axis.x * axis.y + axis.z * s, oc * axis.y * axis.y + c,          oc * axis.y * axis.z - axis.x * s, 0.0,
		oc * axis.z * axis.x - axis.y * s, oc * axis.y * axis.z + axis.x * s, oc * axis.z * axis.z + c,			 0.0,
		0.0,                               0.0,                               0.0,								 1.0
	};
	return mat;
}

// multiply a matrix with a vector (assumes w component of vector is 1.0f) 
Vector matMultVector(array<float> rotMat, Vector v)
{
	Vector outv;
	outv.x = rotMat[0]*v.x + rotMat[4]*v.y + rotMat[8]*v.z  + rotMat[12];
	outv.y = rotMat[1]*v.x + rotMat[5]*v.y + rotMat[9]*v.z  + rotMat[13];
	outv.z = rotMat[2]*v.x + rotMat[6]*v.y + rotMat[10]*v.z + rotMat[14];
	return outv;
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