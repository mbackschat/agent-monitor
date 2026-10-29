"""Offline normalization and replay of the already completed bounded calibration."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import statistics
import sys


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def intern(value, table):
    if value not in table:
        table.append(value)
    return table.index(value)


def condense(raw_path, preflight_path, model_path):
    raw, preflight = (json.loads(Path(p).read_text()) for p in [raw_path, preflight_path])
    assert len(raw['observations']) == 60 and len(raw['events']) == 32
    assert raw['watchdogTriggered'] is False and raw['nativeExecuted'] is True
    assert raw['sourceSHA256'] == preflight['sourceSHA256']
    assert raw['supervisorSHA256'] == preflight['supervisorSHA256']
    def privacy(value):
        if isinstance(value, dict):
            assert not {'pid', 'PID', 'registryID', 'rawRegistryID', 'birth', 'path', 'creator'} & value.keys()
            for item in value.values(): privacy(item)
        elif isinstance(value, list):
            for item in value: privacy(item)
        elif isinstance(value, str):
            assert '/Users/' not in value and '/private/' not in value
    privacy(raw)
    inventory_sets, tuple_sets, intents, observations = [], [], [], []
    for sample in raw['observations']:
        assert sample['status'] == 'available' and sample['lifetimeVerified'] is True
        assert sample['readStartSeconds'] <= sample['readEndSeconds']
        inventory, tuples = [], []
        for client in sample['ownClients']:
            inventory.append({k:v for k,v in client.items() if k not in ['aggregateRawCounter','recordCount','recordsInArrayOrder']})
            assert client['classReturnCode'] == client['propertyKeysReturnCode'] == 0
            assert client['propertyKeysStatus'] == 'available'
            if client['className'] != 'AGXDeviceUserClient':
                assert client['usageStatus'] == 'not_requested_for_other_class'
                continue
            assert client['clientOrdinal'] == 1 and client['usageStatus'] == 'available'
            for index, record in enumerate(client['recordsInArrayOrder']):
                assert record['arrayIndex'] == index and record['API'] == 'Metal' and record['status'] == 'available'
                assert record['fieldNames'] == ['API','accumulatedGPUTime','lastSubmittedTime']
                pair = []
                for name in ['accumulatedGPUTime','lastSubmittedTime']:
                    numeric = record[name]
                    assert numeric['objcType'] == 'q' and numeric['status'] == 'available'
                    assert set(numeric) == {'decimal','objcType','status'}
                    assert 0 <= int(numeric['decimal']) <= (1<<64)-1
                    pair.append(numeric['decimal'])
                tuples.append(pair)
            assert client['recordCount'] == len(tuples)
            assert int(client['aggregateRawCounter']) == sum(int(x[0]) for x in tuples)
        assert sample['clientCount'] == len(inventory) and sample['recordCount'] == len(tuples)
        observations.append([sample['label'],sample['readStartSeconds'],sample['readEndSeconds'],
                             intern(inventory,inventory_sets),intern(tuples,tuple_sets),
                             intern(sample['applicationReferenceIntent'],intents)])
    tasks = [event['selfTaskGPU'] for event in raw['events']]
    assert all(value == tasks[0] for value in tasks)
    assert tasks[0] == {'kernReturn':0,'requestedWordCount':26,'returnedWordCount':26,
                        'scope':'worker_self','status':'available','taskGPUUtilisationRaw':'0'}
    event_map = {event['label']:event for event in raw['events']}
    batch_events = [event for event in raw['events'] if 'submissions' in event]
    assert len(batch_events) == 6 and sum(x['submissions'] for x in batch_events) == 384
    timings = []
    for event in batch_events:
        assert event['submissions'] == 64 and event['outputsVerified'] is True
        assert event['gpuTimestampOverlaps'] == 0 and event['gpuUnionStatus'] == 'available'
        assert event['gpuValidIntervalUnionSeconds'] == event['gpu']['sumSeconds']
        first = event_map[event['label'].replace('after_', 'first_', 1)]
        for name in ['gpu','kernel','hostCommitToCompletionHandler','hostCommitToWaitReturn']:
            metric, first_metric = event[name],first[name]
            assert metric['validCount'] == 64 and metric['invalidCount'] == 0 and metric['status'] == 'available'
            assert first_metric['validCount'] == 1 and first_metric['invalidCount'] == 0
            assert first_metric['sumSeconds'] == first_metric['firstCommandSeconds'] == metric['firstCommandSeconds']
            assert first_metric['minimumSeconds'] == first_metric['maximumSeconds'] == first_metric['sumSeconds']
        timings.append({k:v for k,v in event.items() if k not in ['applicationReferenceIntent','selfTaskGPU']})
    return {
        'provenance': {'rawResultSHA256':sha(raw_path),'sourceSHA256':raw['sourceSHA256'],
            'supervisorSHA256':raw['supervisorSHA256'],'modelSHA256':sha(model_path),
            'analysisSourceSHA256':sha(__file__),'completedUTC':raw['completedUTC'],
            'compiler':preflight['compiler'],'sdk':preflight['sdk'],
            'deviceFromWorkerEvent':event_map['after_device']['device'],
            'environmentAfterRun':{'macOS':'27.0.1','build':'26A434','architecture':'arm64',
                'basis':'parent separately read sw_vers/uname after the run; not emitted by worker'}},
        'run':{'workerAndObservationWallSeconds':raw['workerAndObservationWallSeconds'],
            'watchdogSeconds':20,'watchdogTriggered':False,'workerCheckpoints':32,'observations':60,
            'commands':384,'explicitDataBufferBytes':event_map['before_queue_a_creation']['explicitDataBufferBytes'],
            'setupSeconds':event_map['before_queue_a_creation']['setupSeconds'],
            'allCommandsCompletedWithoutErrorAndVerifiedByWorker':True,
            'allObserverReadsAvailableAndLifetimeVerified':True},
        'recordEncoding':{'fieldNames':['API','accumulatedGPUTime','lastSubmittedTime'],'API':'Metal',
            'numericEncoding':{'objcType':'q','status':'available','valueFormat':'exact decimal string'},
            'tupleColumns':['accumulatedGPUTime','lastSubmittedTime'],
            'arrayOrder':'tuples retain original arrayIndex by position; no persistent record identity implied',
            'tupleSetIndexMeaning':'compression reference to a complete tuple array, not a record identity'},
        'inventorySets':inventory_sets,'tupleSets':tuple_sets,'applicationReferenceIntents':intents,
        'observationColumns':['label','readStartSeconds','readEndSeconds','inventorySetIndex','tupleSetIndex','referenceIntentIndex'],
        'observations':observations,'workerEventLabels':[e['label'] for e in raw['events']],
        'selfTaskGPU':{'sampleCount':32,'allSamplesIdentical':tasks[0],'labels':'workerEventLabels'},
        'batchTimings':timings,'firstCommandEventReduction':'Each first-event timing had one valid sample; sum/min/max equal the retained firstCommandSeconds.',
        'selectedEndpointReplays':raw['selectedEndpointReplays'],'limits':raw['limits'],
    }


def analyze(compact, model_path):
    assert sha(model_path) == compact['provenance']['modelSHA256']
    spec = importlib.util.spec_from_file_location('gpu_matching_research',model_path)
    model = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = model
    spec.loader.exec_module(model)
    observations = {}
    dense_matching = dense_guarded = rejected = 0
    previous = None
    for row in compact['observations']:
        label,start,end,inventory_id,tuples_id,intent_id = row
        inventory = compact['inventorySets'][inventory_id]
        tuples = compact['tupleSets'][tuples_id]
        has_agx = any(c['className']=='AGXDeviceUserClient' for c in inventory)
        values = [int(pair[0]) for pair in tuples]
        observations[label] = {'values':values,'timestamps':[int(pair[1]) for pair in tuples],
                                'start':start,'end':end,'inventory':inventory,'intent':intent_id}
        if not has_agx:
            previous = None
            continue
        if previous is not None:
            dense_matching += model.minimum_increment(previous,values).lower_bound
            delta = sum(values)-sum(previous)
            if len(previous)==len(values) and delta>=0:
                dense_guarded += delta
            else:
                rejected += 1
        previous = values
    batches = []
    for timing in compact['batchTimings']:
        name = timing['label'][6:]
        before = observations[f'before_{name}@0ms']
        first = observations[f'first_{name}@0ms']
        after = observations[f'after_{name}@0ms']
        raw = sum(after['values'])-sum(before['values'])
        first_raw = sum(first['values'])-sum(before['values'])
        row = {'name':name,'rawIncrement64':raw,'firstCommandRawIncrement':first_raw,
            'rawIncrementRemaining63':raw-first_raw,
            'conditionalRawNanosecondsToGPUElapsedRatio':raw/1e9/timing['gpu']['sumSeconds'],
            'conditionalRawNanosecondsToHostHandlerRatio':raw/1e9/timing['hostCommitToCompletionHandler']['sumSeconds'],
            'propertyReadIntervalBoundsRemaining63Seconds':[after['start']-first['end'],after['end']-first['start']]}
        row['matchingRemaining63TimingSeconds'] = {metric:timing[metric]['sumSeconds']-timing[metric]['firstCommandSeconds']
            for metric in ['gpu','kernel','hostCommitToCompletionHandler','hostCommitToWaitReturn']}
        batches.append(row)
    isolated = {row['name']:row['rawIncrement64'] for row in batches}
    replays=[]
    for index, spec in enumerate(compact['selectedEndpointReplays']):
        before,after=observations[spec['start']],observations[spec['end']]
        actual=isolated['a2'] if index==0 else isolated['a3']+isolated['c1']
        lower=model.minimum_increment(before['values'],after['values']).lower_bound
        assert lower==model.exhaustive_oracle(before['values'],after['values'])
        replays.append(dict(spec,before=before['values'],after=after['values'],
            aggregateDelta=sum(after['values'])-sum(before['values']),matchingLowerBound=lower,
            controlledIsolatedRawIncrements=actual,conditionalBoundShortfall=actual-lower,
            countGuardWouldReject=len(before['values'])!=len(after['values'])))
    read_ms=[(row[2]-row[1])*1000 for row in compact['observations']]
    assert dense_matching == dense_guarded == sum(isolated.values()) == 66835624
    assert rejected==6
    assert replays[0]['matchingLowerBound']==10610167 and replays[1]['matchingLowerBound']==22073041
    return {'denseConditionalMatchingLedger':dense_matching,'denseGuardedAggregateLedger':dense_guarded,
        'guardedExcludedTransitionsAfterBaseline':rejected,'isolatedDriverIncrementSum':sum(isolated.values()),
        'batches':batches,'endpointReplays':replays,
        'readerWallMilliseconds':{'minimum':min(read_ms),'median':statistics.median(read_ms),
                                'maximum':max(read_ms),'sum':sum(read_ms)},
        'interpretation':'Raw driver increments are not independently calibrated GPU work; conditional matching premises remain unproved outside this fixture.'}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--raw',type=Path)
    parser.add_argument('--preflight',type=Path)
    parser.add_argument('--compact',type=Path,required=True)
    parser.add_argument('--model',type=Path,required=True)
    args=parser.parse_args()
    if args.raw:
        result=condense(args.raw,args.preflight,args.model)
        result['derivedAnalysis']=analyze(result,args.model)
        args.compact.write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    else:
        result=json.loads(args.compact.read_text())
        assert analyze(result,args.model)==result['derivedAnalysis']
    print(json.dumps(result['derivedAnalysis'],indent=2,sort_keys=True))


if __name__=='__main__':
    main()
