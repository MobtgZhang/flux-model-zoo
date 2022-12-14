using Flux,Statistics
using Flux.Data:DataLoader
using Flux:onehotbatch,onecold,@epochs
using Flux:logitcrossentropy
using Base:@kwdef
using BSON:@load,@save
using CUDA
using MLDatasets

function getdata(args)
    ENV["DATADEPS_ALWAYS_ACCEPT"] = "true"

    # Loading Dataset
    xtrain, ytrain = MLDatasets.MNIST(split=:train)[:]
    xtest, ytest = MLDatasets.MNIST(split=:test)[:]

    # Reshape Data in order to flatten each image into a linear array
    xtrain = Flux.flatten(xtrain)
    xtest = Flux.flatten(xtest)

    # One-hot-encode the labels
    ytrain, ytest = onehotbatch(ytrain, 0:9), onehotbatch(ytest, 0:9)
    # Create DataLoaders (mini-batch iterators)

    train_loader = DataLoader((xtrain,ytrain), batchsize=args.batchsize, shuffle=true)
    test_loader = DataLoader((xtest,ytest), batchsize=args.batchsize)
    return train_loader,test_loader
end
function build_model(;imgsize=(28,28,1),nclasses=10)
    model =  Chain(
        Dense(prod(imgsize),32,relu),
        Dense(32,nclasses)
    )
    return model
end
function loss_and_accuracy(data_loader,model,device)
    acc = 0
    ls = 0.0f0
    num = 0
    for (x,y) in data_loader
        x,y = device(x),device(y)
        y_pred = model(x)
        ls += logitcrossentropy(y_pred,y)
        acc += sum(onecold(cpu(model(x))) .== onecold(cpu(y)))
        num += size(x,2)
    end
    return ls/num,acc/num
end
@kwdef mutable struct Args
    eta::Float64 = 3e-4
    batchsize::Int = 256
    epochs::Int = 10
    use_cuda::Bool = true
    log_path::String = "./log"
end
function train(;kws...)
    args = Args(;kws...)
    if !ispath(args.log_path)
        mkdir(args.log_path)
    end
    
    if CUDA.functional() && args.use_cuda
        @info "Training data on CUDA GPU"
        CUDA.allowscalar(false)
        device = gpu
    else
        @info "Training data on CPU"
        device = cpu
    end

    # create train test dataloader
    train_loader,test_loader = getdata(args)

    # construct the model
    model = build_model() |> device
    ps = Flux.params(model)
    # optimizer
    optimizer = ADAM(args.eta)
    # Training process
    best_acc = 0.0
    save_model_file = joinpath(args.log_path,"mlp-model.bson")
    for epoch in 1:args.epochs
        for (x,y) in train_loader
            x,y = device(x),device(y)
            gs = gradient(()->logitcrossentropy(model(x),y),ps)
            Flux.Optimise.update!(optimizer,ps,gs)
        end
        # test data
        train_loss,train_acc = loss_and_accuracy(train_loader,model,device)
        test_loss,test_acc = loss_and_accuracy(test_loader,model,device)
        println("  Epoch=$epoch")
        println("  train_loss = $train_loss, train_accuracy = $train_acc")
        println("  test_loss = $test_loss, test_accuracy = $test_acc")
        if best_acc<test_acc
            best_acc = test_acc
            tmpmodel = model |> cpu

            @save save_model_file tmpmodel
        end
    end
end
function main()
    train()
end
main()


