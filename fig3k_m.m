%% Load the data
load 'Linear_track_data/ca_data'
load 'Linear_track_data/ca_time'
load 'Linear_track_data/behav_vec'
load 'Linear_track_data/behav_time'

%% Parameters used to binarize the calcium traces
sampling_frequency = 30; % This data set has been sampled at 30 images per second
z_threshold = 2; % A 2 standard-deviation threshold is usually optimal to differentiate calcium ativity from background noise

%% Interpolate behavior
% In most cases, behavior data has to be interpolated to match neural temporal
% activity assuming it has a lower sampling frequency than neural activity
[interp_behav_vec] = interpolate_behavior(behav_vec, behav_time, ca_time);
interp_behav_vec(end) = interp_behav_vec(end-1);
%% Compute velocities
% In this example, we will ignore moments when the mouse is immobile
[velocity] = extract_velocity(interp_behav_vec, ca_time);

%% Find periods of immobility
% This will be usefull later to exclude immobility periods from analysis
min_speed_threshold = 5; % 2 cm.s-1
running_ts = velocity > min_speed_threshold;

%% Compute occupancy and joint probabilities
bin_size = 3;
% Make sure that your binning vector includes every data point of
% interp_behav_vec using the min/max function:
bin_vector = min(interp_behav_vec):bin_size:max(interp_behav_vec)+bin_size;
bin_centers_vector = bin_vector + bin_size/2;
bin_centers_vector(end) = [];

%% Decoding
% First let's binarize traces from all cells
binarized_data = zeros(size(ca_data));
for cell_i = 1:size(ca_data,2)
    binarized_data(:,cell_i) = extract_binary(ca_data(:,cell_i), sampling_frequency, z_threshold);
end

%% Select the frames that are going to be used to train the decoder
training_set_creation_method = 'random'; % 'odd', odd timestamps; 'first_portion', first portion of the recording; 3, 'random' random frames
training_set_portion = 0.5;
noise_level = 0:0.1:1;

%% Let us compare the average decoding error using different number of cells
for noise_i = 1:length(noise_level)
    display(['Computing decoding error using a ' num2str(noise_level(noise_i)) ' portion of noise'])
    for trial_i = 1:30
        disp(['Trial ' num2str(trial_i) ' out of 30'])
        training_ts = create_training_set(ca_time, training_set_creation_method, training_set_portion);
        training_ts(running_ts == 0) = 0;
        for cell_i = 1:size(binarized_data,2)
            [MI(cell_i), PDF(:,cell_i), occupancy_vector, prob_being_active(cell_i), tuning_curve_data(:,cell_i) ] = extract_1D_information(binarized_data(:,cell_i), interp_behav_vec, bin_vector, training_ts);
        end
        
        if noise_level(noise_i) ~= 0
        [tuning_curve_data] = create_noisy_tuning_curves(tuning_curve_data,noise_level(noise_i));
        end
        
        decoding_ts = ~training_ts;
        decoding_ts(running_ts == 0) = 0;
        occupancy_vector = occupancy_vector./occupancy_vector*(1/length(occupancy_vector));
        cell_used = logical(ones(size(ca_data,2),1));
        [decoded_probabilities] = bayesian_decode1D(binarized_data, occupancy_vector, prob_being_active, tuning_curve_data, cell_used);
        [max_decoded_prob, decoded_bin] = max(decoded_probabilities,[],1);
        decoded_position = bin_centers_vector(decoded_bin);
        actual_bin = nan*interp_behav_vec;
        actual_position = nan*interp_behav_vec;
        for bin_i = 1:length(bin_vector)-1
            position_idx = find(interp_behav_vec>bin_vector(bin_i) & interp_behav_vec < bin_vector(bin_i+1));
            actual_bin(position_idx) = bin_i;
            actual_position(position_idx) = bin_centers_vector(bin_i);
        end
        decoded_bin(~decoding_ts) = nan;
        decoded_position(~decoding_ts) = nan;
        decoded_probabilities(:,~decoding_ts) = nan;
        actual_bin(~decoding_ts) = nan;
        actual_position(~decoding_ts) = nan;
        actual_bin = actual_bin';
        actual_position =  actual_position';
        decoding_agreement_vector = double(decoded_bin == actual_bin);
        decoding_agreement_vector(isnan(decoded_bin)) = nan;
        decoding_agreement_vector(isnan(actual_bin)) = nan;
        decoding_agreement_vector(isnan(decoding_agreement_vector)) = [];
        decoding_agreement_noise_level{noise_i}(trial_i) = sum(decoding_agreement_vector)./length(decoding_agreement_vector);
        decoding_error = actual_position - decoded_position;
        mean_decoding_error_noise_level{noise_i}(trial_i) = mean(abs(decoding_error), 'omitnan');
    end
end