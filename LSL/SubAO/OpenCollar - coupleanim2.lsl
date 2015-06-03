////////////////////////////////////////////////////////////////////////////////////
// ------------------------------------------------------------------------------ //
//                           OpenCollar - coupleanim2                             //
//                                 version 3.992                                  //
// ------------------------------------------------------------------------------ //
// Licensed under the GPLv2 with additional requirements specific to Second Life® //
// and other virtual metaverse environments.  ->  www.opencollar.at/license.html  //
// ------------------------------------------------------------------------------ //
// ©   2008 - 2014  Individual Contributors and OpenCollar - submission set free™ //
// ------------------------------------------------------------------------------ //
//          github.com/OpenCollar/OpenCollarHypergrid/tree/inworldz               //
// ------------------------------------------------------------------------------ //
////////////////////////////////////////////////////////////////////////////////////
key partner;
float timeout = 30.0;//time for the potential kissee to respond before we give up

//MESSAGE MAP
integer COMMAND_OWNER = 500;
integer CPLANIM_PERMREQUEST = 7002;//id should be av's key, str should be cmd name "hug", "kiss", etc
integer CPLANIM_PERMRESPONSE = 7003;//str should be "1" for got perms or "0" for not.  id should be av's key
integer CPLANIM_START = 7004;//str should be valid anim name.  id should be av
integer CPLANIM_STOP = 7005;//str should be valid anim name.  id should be av
string stopstring = "stop";
integer stopchannel = 99;
integer listener;
string anim;

string FirstName(string name)
{
    return llList2String(llParseString2List(name, [" "], []), 0);
}

default
{    
    link_message(integer sender, integer num, string str, key id)
    {    
        if (num == CPLANIM_PERMREQUEST)
        {
            partner = id;
            llRequestPermissions(partner, PERMISSION_TRIGGER_ANIMATION);
            llInstantMessage(partner, FirstName(llKey2Name(llGetOwner())) + " would like give you a " + str + ". Click [Yes] to accept." );
            llSetTimerEvent(timeout);
        }
        else if (num == CPLANIM_START)
        {
            llStartAnimation(str);//note that we don't double check for permissions here, so if the coupleanim1 script sends its messages out of order, this might fail
            anim = str;
            listener = llListen(stopchannel, "", partner, stopstring);
            llInstantMessage(partner, "If you would like to stop the animation early, say /" + (string)stopchannel + stopstring + " to stop.");    
        }
        else if (num == CPLANIM_STOP)
            llStopAnimation(str);
    } 
    
    run_time_permissions(integer perm)
    {
        if (perm & PERMISSION_TRIGGER_ANIMATION)
        {
            key id = llGetPermissionsKey();
            if (id == partner)
            {
                llSetTimerEvent(0.0);
                llMessageLinked(LINK_THIS, CPLANIM_PERMRESPONSE, "1", partner);                
            }
            else
                llInstantMessage(id, "Sorry, but the request timed out.");
        }
    }
    
    timer()
    {
        llSetTimerEvent(0.0);
        llListenRemove(listener);
        llMessageLinked(LINK_THIS, CPLANIM_PERMRESPONSE, "0", partner);
        partner = NULL_KEY;
    }
    
    listen(integer channel, string name, key id, string message)
    {
        llListenRemove(listener);
        if (channel == stopchannel)
            llMessageLinked(LINK_THIS, COMMAND_OWNER, "stopcouples", id);
    }
}