// This is a WCT configuration file for use in a WC/LS simulation job.
// 
// It is expected to be named inside a FHiCL configuration.  The names
// for the "inputer" and "outputer" converter components MUST match
// what is used here in wcls_input and wcls_output objects.
//

local wc = import "wirecell.jsonnet";
local g = import "pgraph.jsonnet";

// overlay: no noise, misconfigure channels
// Digitizer output: always positive + able to assign a tag to the frame
// baselines have to be there, do we need to change, easy to subtract in overlays?
local base = import "pgrapher/experiment/uboone/simparams.jsonnet";
local params = base {
    adc: super.adc{
  //      baselines: [2000*wc.millivolt, 2000*wc.millivolt, 2000*wc.millivolt],
  //      resolution: base.adc.resolution+1,
  //      fullscale: [0*wc.volt, base.adc.fullscale[1]*2],
    },
};


local tools_maker = import "pgrapher/common/tools.jsonnet";
local tools = tools_maker(params);
local sim_maker = import "pgrapher/experiment/uboone/sim.jsonnet";
local sim = sim_maker(params, tools);

local wcls_maker = import "pgrapher/ui/wcls/nodes.jsonnet";
local wcls = wcls_maker(params, tools);

// for dumping numpy array for debugging
local io = import "pgrapher/common/fileio.jsonnet";

//local nf_maker = import "pgrapher/experiment/uboone/nf.jsonnet";
local chndb_maker = import "pgrapher/experiment/uboone/chndb.jsonnet";

//local sp_maker = import "pgrapher/experiment/uboone/sp.jsonnet";

local anode = tools.anodes[0];
local rng = tools.random; // BR insert
    
// This tags the output frame of the WCT simulation and is used in a
// couple places so define it once.
local sim_adc_frame_tag = "orig";

// Collect the WC/LS input converters for use below.  Make sure the
// "name" matches what is used in the FHiCL that loads this file.
// art_label (producer, e.g. plopper) and art_instance (e.g. bogus) may be needed
// fudge factor to account for MC/data gain e.g. 180/250=0.72
local fudge = std.extVar("gain_fudge_factor");
local wcls_input = {
    depos: wcls.input.depos(name="", scale=-1.0*fudge, art_tag="ionization"),
};

// Collect all the wc/ls output converters for use below.  Note the
// "name" MUST match what is used in theh "outputers" parameter in the
// FHiCL that loads this file.
local wcls_output = {
    // ADC output from simulation
    sim_digits: wcls.output.digits(name="simdigits", tags=[sim_adc_frame_tag]),
    
    // The noise filtered "ADC" values.  These are truncated for
    // art::Event but left as floats for the WCT SP.  Note, the tag
    // "raw" is somewhat historical as the output is not equivalent to
    // "raw data".
    //nf_digits: wcls.output.digits(name="nfdigits", tags=["raw"]),

    // The output of signal processing.  Note, there are two signal
    // sets each created with its own filter.  The "gauss" one is best
    // for charge reconstruction, the "wiener" is best for S/N
    // separation.  Both are used in downstream WC code.
    //sp_signals: wcls.output.signals(name="spsignals", tags=["gauss"]),
};


// fill SimChannel
local wcls_simchannel_sink = g.pnode({
    type: 'wclsSimChannelSink',
    name: 'postdrift',
    data: {
        anode: wc.tn(anode),
        rng: wc.tn(rng),
        tick: 0.5*wc.us,
        start_time: -1.6*wc.ms, //0.0*wc.s,
        readout_time: self.tick*9600,
        nsigma: 3.0,
        drift_speed: params.lar.drift_speed,
        uboone_u_to_rp: 100*wc.mm,
        uboone_v_to_rp: 100*wc.mm,
        uboone_y_to_rp: 100*wc.mm,
        u_time_offset: 0.0*wc.us,
        v_time_offset: 0.0*wc.us,
        y_time_offset: 0.0*wc.us,
        use_energy: true,
    },
}, nin=1, nout=1, uses=[tools.anode]);


local drifter = sim.drifter;

// Signal simulation.
//local ductors = sim.make_anode_ductors(anode);
//local md_pipes = sim.multi_ductor_pipes(ductors);
//local ductor = sim.multi_ductor_graph(anode, md_pipes, "mdg");
local ductor = sim.signal;

local miscon = sim.misconfigure(params);

// Noise simulation adds to signal.
//local noise_model = sim.make_noise_model(anode, sim.empty_csdb);
//local noise_model = sim.make_noise_model(anode, sim.miscfg_csdb);
//local noise = sim.add_noise(noise_model);

local digitizer = sim.digitizer(anode, tag="orig");


local sink = sim.frame_sink;
//local sink = sim.depo_sink;

local magnifio = g.pnode({
    type: "MagnifySink",
    name: "origmag",
    data: {
        output_filename: "sim-overlay-check.root",
        root_file_mode: "RECREATE",
        frames: ["orig"],
        anode: wc.tn(anode),
    },
}, nin=1, nout=1);
local graph = g.pipeline([wcls_input.depos,
                          drifter, 
                          wcls_simchannel_sink,
                          ductor, miscon, digitizer,
                          wcls_output.sim_digits,
                          //magnifio,
                          sink]);


local app = {
    type: "Pgrapher",
    data: {
        edges: g.edges(graph),
    },
};

// Finally, the configuration sequence which is emitted.

g.uses(graph) + [app]
